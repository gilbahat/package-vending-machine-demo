#!/usr/bin/env python3
"""
build_manifest.py -- produce the signed allowlist the vending machine boots on.

The wire format is defined in spec/VendManifest.3d and parsed inside the
unikernel by an EverParse-generated validator. This script is the only writer
of that format; it is deliberately kept simple enough to check against the .3d
by eye.

    signed manifest := Ed25519 signature (64 bytes) || body
    body            := magic "VMC1"     u32be
                       format_version 1 u16be
                       reserved       0 u16be
                       entries_len      u32be
                       entries          (entries_len bytes)
    entry           := ecosystem u8 (0 = PyPI, 1 = npm)
                       name_len  u8 (1..128)
                       name      name_len bytes

The signature covers the body exactly. The unikernel checks it BEFORE the
bytes reach the parser, and the parser then requires that the body be consumed
exactly -- so there is no region of the file that is signed but unparsed, or
parsed but unsigned.

Requires: cryptography  (pip install cryptography)

Copyright (c) 2026. SPDX-License-Identifier: ISC
"""
import argparse
import pathlib
import struct
import sys

from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)
from cryptography.hazmat.primitives import serialization

MAGIC = 0x564D4331  # "VMC1"
FORMAT_VERSION = 1
MAX_NAME_LEN = 128
MAX_ENTRIES_LEN = 1048576

ECOSYSTEMS = {"pypi": 0, "npm": 1}


def parse_package_list(path: pathlib.Path):
    """Read 'ecosystem:name' lines, ignoring blanks and # comments."""
    entries = []
    seen = set()
    for lineno, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if ":" not in line:
            sys.exit(f"{path}:{lineno}: expected 'ecosystem:name', got {raw!r}")
        eco, name = line.split(":", 1)
        eco, name = eco.strip().lower(), name.strip()
        if eco not in ECOSYSTEMS:
            sys.exit(f"{path}:{lineno}: unknown ecosystem {eco!r}; "
                     f"expected one of {sorted(ECOSYSTEMS)}")
        encoded = name.encode("ascii", errors="strict")
        if not 1 <= len(encoded) <= MAX_NAME_LEN:
            sys.exit(f"{path}:{lineno}: name must be 1..{MAX_NAME_LEN} bytes")
        key = (eco, name)
        if key in seen:
            continue          # duplicates are harmless; drop them
        seen.add(key)
        entries.append((ECOSYSTEMS[eco], encoded))
    # Sort so the manifest is a deterministic function of the input set.
    entries.sort()
    return entries


def build_body(entries) -> bytes:
    blob = b"".join(
        struct.pack(">BB", eco, len(name)) + name for eco, name in entries
    )
    if len(blob) > MAX_ENTRIES_LEN:
        sys.exit(f"entry list is {len(blob)} bytes, over the "
                 f"{MAX_ENTRIES_LEN} cap in the .3d spec")
    return struct.pack(">IHHI", MAGIC, FORMAT_VERSION, 0, len(blob)) + blob


def cmd_keygen(args):
    outdir = pathlib.Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    priv = Ed25519PrivateKey.generate()

    seed = priv.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption(),
    )
    pub = priv.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )

    (outdir / "manifest.key").write_bytes(seed)
    (outdir / "manifest.key").chmod(0o600)
    (outdir / "manifest.pub").write_bytes(pub)

    print(f"wrote {outdir/'manifest.key'} (KEEP PRIVATE)")
    print(f"wrote {outdir/'manifest.pub'}")
    print(f"public key: {pub.hex()}")


def cmd_build(args):
    entries = parse_package_list(pathlib.Path(args.packages))
    body = build_body(entries)

    seed = pathlib.Path(args.key).read_bytes()
    if len(seed) != 32:
        sys.exit(f"{args.key}: expected a 32-byte Ed25519 seed, "
                 f"got {len(seed)} bytes")
    priv = Ed25519PrivateKey.from_private_bytes(seed)
    sig = priv.sign(body)

    out = pathlib.Path(args.out)
    out.write_bytes(sig + body)

    n_pypi = sum(1 for e, _ in entries if e == 0)
    n_npm = sum(1 for e, _ in entries if e == 1)
    print(f"wrote {out}: {len(entries)} entries "
          f"({n_pypi} pypi, {n_npm} npm), {len(sig) + len(body)} bytes")


def cmd_verify(args):
    """Independently check a manifest, as the unikernel will."""
    data = pathlib.Path(args.manifest).read_bytes()
    if len(data) < 64:
        sys.exit("file is shorter than a signature")
    sig, body = data[:64], data[64:]

    pub = Ed25519PublicKey.from_public_bytes(
        pathlib.Path(args.pubkey).read_bytes())
    try:
        pub.verify(sig, body)
    except Exception:
        sys.exit("SIGNATURE INVALID")

    magic, ver, reserved, entries_len = struct.unpack(">IHHI", body[:12])
    if magic != MAGIC:
        sys.exit(f"bad magic {magic:#x}")
    if ver != FORMAT_VERSION:
        sys.exit(f"unsupported format version {ver}")
    if reserved != 0:
        sys.exit("reserved field is not zero")
    if 12 + entries_len != len(body):
        sys.exit(f"entries_len {entries_len} does not match body "
                 f"({len(body) - 12} bytes available)")

    off, names = 12, []
    while off < len(body):
        eco, name_len = body[off], body[off + 1]
        name = body[off + 2:off + 2 + name_len].decode("ascii")
        names.append(("pypi" if eco == 0 else "npm", name))
        off += 2 + name_len

    print(f"signature OK, {len(names)} entries")
    for eco, name in names:
        print(f"  {eco}:{name}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("keygen", help="generate a manifest signing keypair")
    p.add_argument("--outdir", default="keys")
    p.set_defaults(func=cmd_keygen)

    p = sub.add_parser("build", help="build and sign a manifest")
    p.add_argument("--packages", required=True,
                   help="text file of 'ecosystem:name' lines")
    p.add_argument("--key", required=True, help="32-byte Ed25519 seed")
    p.add_argument("--out", default="manifest.bin")
    p.set_defaults(func=cmd_build)

    p = sub.add_parser("verify", help="verify and dump a signed manifest")
    p.add_argument("manifest")
    p.add_argument("--pubkey", required=True)
    p.set_defaults(func=cmd_verify)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
