#!/usr/bin/env bash
#
# run-hvt.sh -- boot the vending machine under solo5-hvt.
#
# REQUIRES A LINUX HOST WITH /dev/kvm. solo5-hvt is a hardware-virtualised
# tender; it will not run on macOS, and Docker Desktop on Apple Silicon does
# not expose nested virtualisation. Standard GitHub Actions runners have no
# KVM either.
#
# Sets up a tap device so the unikernel has exactly one network interface and
# no other route to anything.
#
# Copyright (c) 2026. SPDX-License-Identifier: ISC

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-$ROOT/build/vend.hvt}"
TAP="${TAP:-tap100}"
HOST_IP="${HOST_IP:-10.0.0.1}"
GUEST_IP="${GUEST_IP:-10.0.0.2}"
MEM="${MEM:-128}"

if [ ! -f "$IMAGE" ]; then
  echo "no unikernel at $IMAGE -- run 'make unikernel' first" >&2
  exit 1
fi

if [ ! -e /dev/kvm ]; then
  cat >&2 <<'EOF'
/dev/kvm is not present.

solo5-hvt is hardware-virtualised and needs KVM. This will not work on macOS,
inside Docker Desktop on Apple Silicon, or on a standard GitHub-hosted runner.
Use a Linux host with virtualisation enabled.
EOF
  exit 1
fi

if ! command -v solo5-hvt >/dev/null 2>&1; then
  echo "solo5-hvt not on PATH -- install the solo5 opam package" >&2
  exit 1
fi

echo "==> setting up $TAP ($HOST_IP, guest expected at $GUEST_IP)"
if ! ip link show "$TAP" >/dev/null 2>&1; then
  sudo ip tuntap add "$TAP" mode tap
  sudo ip addr add "$HOST_IP/24" dev "$TAP"
  sudo ip link set dev "$TAP" up
fi

# The unikernel needs to reach pypi.org and registry.npmjs.org, so the host
# must forward and NAT for it. This is the ONLY route it has.
UPLINK="$(ip route show default | awk '/default/ {print $5; exit}')"
if [ -n "${UPLINK:-}" ]; then
  echo "==> enabling NAT via $UPLINK"
  sudo sysctl -qw net.ipv4.ip_forward=1
  sudo iptables -t nat -C POSTROUTING -s "${HOST_IP%.*}.0/24" -o "$UPLINK" -j MASQUERADE 2>/dev/null \
    || sudo iptables -t nat -A POSTROUTING -s "${HOST_IP%.*}.0/24" -o "$UPLINK" -j MASQUERADE
fi

echo "==> the tender's view of what this image may touch:"
solo5-elftool query-manifest "$IMAGE" || true

echo
echo "==> booting; the machine will answer on http://$GUEST_IP:8080"
echo "    try:  curl http://$GUEST_IP:8080/v1/status"
echo "          bash attack/replay.sh http://$GUEST_IP:8080"
echo

exec solo5-hvt --mem="$MEM" --net:service="$TAP" -- "$IMAGE" \
  --ipv4="$GUEST_IP/24" --ipv4-gateway="$HOST_IP"
