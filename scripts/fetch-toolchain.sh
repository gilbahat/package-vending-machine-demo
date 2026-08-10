#!/usr/bin/env bash
#
# fetch-toolchain.sh -- download the pinned EverParse binary package.
#
# One tarball carries F*, KaRaMeL, 3d, Z3 and clang-format, so this is the
# entire verification toolchain. Checksums below are the digests GitHub
# publishes for the release assets; the download is refused if they do not
# match.
#
# You do NOT need this to build or run the demo -- generated/ is committed.
# You need it to re-verify the proofs and regenerate the C, which is what
# `make verify` does.
#
# Copyright (c) 2026. SPDX-License-Identifier: ISC

set -euo pipefail

EVERPARSE_VERSION="v2026.07.02"
DEST="${DEST:-.toolchain}"

SHA256_DARWIN_ARM64="84b83946a898b519779b900d1e61bd34c8878c3af4fc1cc2c4b88eac3fcf41a5"
SHA256_LINUX_X86_64="fc14fcf2914a6afa8f1085c11adb0b9f8e50290d7d62b366108b762c69dceba7"

case "$(uname -s)/$(uname -m)" in
  Darwin/arm64)        ASSET="everparse_${EVERPARSE_VERSION}_Darwin_arm64.tar.gz";  WANT="$SHA256_DARWIN_ARM64" ;;
  Linux/x86_64)        ASSET="everparse_${EVERPARSE_VERSION}_Linux_x86_64.tar.gz";  WANT="$SHA256_LINUX_X86_64" ;;
  *)
    echo "No pinned EverParse build for $(uname -s)/$(uname -m)." >&2
    echo "EverParse publishes Darwin_arm64, Linux_x86_64 and Windows builds;" >&2
    echo "see https://github.com/project-everest/everparse/releases" >&2
    exit 1
    ;;
esac

URL="https://github.com/project-everest/everparse/releases/download/${EVERPARSE_VERSION}/${ASSET}"

if [ -x "${DEST}/everparse/bin/fstar.exe" ]; then
  echo "toolchain already present in ${DEST}/everparse"
  exit 0
fi

mkdir -p "$DEST"
echo "downloading ${ASSET} (~260 MB)..."
curl -fsSL -o "${DEST}/everparse.tar.gz" "$URL"

echo "verifying checksum..."
if command -v sha256sum >/dev/null 2>&1; then
  GOT="$(sha256sum "${DEST}/everparse.tar.gz" | cut -d' ' -f1)"
else
  GOT="$(shasum -a 256 "${DEST}/everparse.tar.gz" | cut -d' ' -f1)"
fi

if [ "$GOT" != "$WANT" ]; then
  echo "CHECKSUM MISMATCH" >&2
  echo "  expected $WANT" >&2
  echo "  got      $GOT" >&2
  rm -f "${DEST}/everparse.tar.gz"
  exit 1
fi

echo "extracting..."
tar -xzf "${DEST}/everparse.tar.gz" -C "$DEST"
rm -f "${DEST}/everparse.tar.gz"

echo "toolchain ready: ${DEST}/everparse"
"${DEST}/everparse/bin/fstar.exe" --version | head -2
