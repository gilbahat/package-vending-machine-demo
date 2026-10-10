#!/usr/bin/env bash
#
# pvm-net.sh -- the host's half of the chokepoint. Idempotent; run at every
# boot by pvm-net.service before the guest starts. Parameters: /etc/pvm.env.
#
#   sandbox ENI :8080  --DNAT-->  tap100  -->  guest $GUEST_IP:8080
#   guest       --MASQUERADE-->  public ENI  -->  internet, tcp/443 + tcp/853 only
#
# Everything else crossing the host is dropped. The F* proof says the guest
# will only ever *ask* for three hosts; this is the independent, unverified
# second layer that holds even if the guest were fully compromised -- it still
# could not reach private address space, link-local (IMDS), or any port but
# the two it needs.
#
# Copyright (c) 2026. SPDX-License-Identifier: ISC

set -euo pipefail

# shellcheck source=/dev/null
. /etc/pvm.env

TAP=tap100
GUEST_NET="${GUEST_IP%.*}.0/24"

SB_IF="$(ip -o link | awk -v m="$SANDBOX_MAC" 'tolower($0) ~ m {sub(":","",$2); print $2; exit}')"
PUB_IF="$(ip route show default | awk -v sb="$SB_IF" '$5 != sb {print $5; exit}')"
[ -n "$SB_IF" ] && [ -n "$PUB_IF" ] || { echo "cannot identify interfaces" >&2; exit 1; }
echo "public: $PUB_IF  sandbox: $SB_IF  tap: $TAP  guest: $GUEST_IP"

# --- sandbox leg -------------------------------------------------------------
# Static address, no default route. Whatever DHCP/netplan does with this ENI,
# the host must never prefer it as a way out.
ip link set "$SB_IF" up
ip addr replace "$SANDBOX_IP/$SANDBOX_PREFIX" dev "$SB_IF"
while ip route del default dev "$SB_IF" 2>/dev/null; do :; done

# --- the guest's only NIC ----------------------------------------------------
if ! ip link show "$TAP" >/dev/null 2>&1; then
  ip tuntap add "$TAP" mode tap user vend
fi
ip addr replace "$GUEST_GW/24" dev "$TAP"
ip link set "$TAP" up

sysctl -qw net.ipv4.ip_forward=1
sysctl -qw net.ipv6.conf.all.disable_ipv6=1

# --- filter ------------------------------------------------------------------
# Rebuilt from scratch on every run so a rerun cannot accumulate duplicates.
# FORWARD is flushed outright: Docker (disabled after the build) leaves jumps
# into its own chains behind.

iptables -P FORWARD DROP
iptables -F FORWARD

iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# agent -> guest:8080 (already DNAT'd below)
iptables -A FORWARD -i "$SB_IF" -o "$TAP" -d "$GUEST_IP" -p tcp --dport 8080 \
  -m conntrack --ctstate NEW -j ACCEPT

# guest -> internet: never to private, shared, loopback or link-local space
for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 \
           127.0.0.0/8 169.254.0.0/16 224.0.0.0/4; do
  iptables -A FORWARD -i "$TAP" -d "$net" -j DROP
done
iptables -A FORWARD -i "$TAP" -o "$PUB_IF" -p tcp -m multiport --dports 443,853 \
  -m conntrack --ctstate NEW -j ACCEPT

iptables -A FORWARD -j LOG --log-prefix "pvm-fwd-drop: " -m limit --limit 6/min
# (policy DROP)

# INPUT: the host itself offers nothing to the sandbox or to the guest.
iptables -N PVM-IN 2>/dev/null || iptables -F PVM-IN
iptables -A PVM-IN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A PVM-IN -j DROP
for ifc in "$SB_IF" "$TAP"; do
  iptables -C INPUT -i "$ifc" -j PVM-IN 2>/dev/null || iptables -I INPUT -i "$ifc" -j PVM-IN
done

# --- nat ---------------------------------------------------------------------

iptables -t nat -N PVM-PRE 2>/dev/null || iptables -t nat -F PVM-PRE
iptables -t nat -A PVM-PRE -i "$SB_IF" -d "$SANDBOX_IP" -p tcp --dport 8080 \
  -j DNAT --to-destination "$GUEST_IP:8080"
iptables -t nat -C PREROUTING -j PVM-PRE 2>/dev/null || iptables -t nat -I PREROUTING -j PVM-PRE

iptables -t nat -N PVM-POST 2>/dev/null || iptables -t nat -F PVM-POST
iptables -t nat -A PVM-POST -s "$GUEST_NET" -o "$PUB_IF" -j MASQUERADE
iptables -t nat -C POSTROUTING -j PVM-POST 2>/dev/null || iptables -t nat -I POSTROUTING -j PVM-POST

echo "pvm-net: ready"
