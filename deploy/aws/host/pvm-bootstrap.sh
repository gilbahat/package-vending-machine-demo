#!/usr/bin/env bash
#
# pvm-bootstrap.sh -- first-boot provisioning of the vending machine host.
# Run once by cloud-init; parameters come from /etc/pvm.env.
#
#   1. wait for the sandbox-facing ENI (attached after launch) to appear
#   2. build vend.hvt natively, with the repository's own `make unikernel`
#   3. lift the solo5-hvt tender out of the build image
#   4. switch Docker off -- it was only needed for the build
#   5. start pvm-net (tap + firewall) and pvm-vend (the guest)
#
# Progress: /var/log/pvm-bootstrap.log. Success leaves /opt/pvm/READY.
#
# Copyright (c) 2026. SPDX-License-Identifier: ISC

set -euo pipefail
exec > >(tee -a /var/log/pvm-bootstrap.log) 2>&1

# shellcheck source=/dev/null
. /etc/pvm.env

step() { echo; echo "==> [$(date -u +%H:%M:%S)] $*"; }

step "waiting for the sandbox ENI ($SANDBOX_MAC)"
for _ in $(seq 1 120); do
  [ -n "$(ip -o link | awk -v m="$SANDBOX_MAC" 'tolower($0) ~ m {print $2}')" ] && break
  sleep 5
done
ip -o link | grep -qi "$SANDBOX_MAC" || { echo "sandbox ENI never appeared" >&2; exit 1; }

step "installing build dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q --no-install-recommends \
  docker.io docker-buildx git make ca-certificates python3-cryptography \
  iptables libseccomp2

step "fetching $SOURCE_REPO @ $SOURCE_REF"
rm -rf /opt/pvm/src
git clone --depth 1 --branch "$SOURCE_REF" "$SOURCE_REPO" /opt/pvm/src
cd /opt/pvm/src

# A fresh signing key per deployment. It never leaves this host, and only its
# public half is baked into the image.
step "building and signing the allowlist"
make manifest

step "building vend.hvt (the toolchain image takes a while on first build)"
make unikernel
install -m 0644 build/vend.hvt /opt/pvm/vend.hvt

step "extracting the solo5-hvt tender from the build image"
docker run --rm pvm-build:latest sh -c 'cat "$(command -v solo5-hvt)"' \
  > /usr/local/bin/solo5-hvt
chmod 0755 /usr/local/bin/solo5-hvt
docker run --rm -v /opt/pvm:/pvm:ro pvm-build:latest \
  solo5-elftool query-manifest /pvm/vend.hvt | tee /opt/pvm/solo5-manifest.json

# The host is part of the TCB this demo is honest about; a container runtime
# with a root daemon is not something it needs once the image exists.
step "disabling Docker"
systemctl disable --now docker.service docker.socket containerd.service || true

step "starting the vending machine"
id vend >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin vend
usermod -aG kvm vend
systemctl daemon-reload
systemctl enable --now pvm-net.service pvm-vend.service

for _ in $(seq 1 30); do
  journalctl -u pvm-vend --no-pager | grep -q 'listening on 8080' && break
  sleep 2
done
journalctl -u pvm-vend --no-pager | tail -20

date -u > /opt/pvm/READY
step "done"
