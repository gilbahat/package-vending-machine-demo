# Running the escape conditions on AWS

This Terraform stands up the network the July 2026 escape happened in: an
agent with no route to the internet whose **only** reachable service is the
package proxy, which itself straddles the sandbox and the public internet.
The difference is that the proxy is the vending machine.

```
                 internet
                    |
           +--------+---------+   public subnet (IGW route)
           |  eth0  (EIP)     |   guest egress: tcp/443, tcp/853 only
           |  [ vend.hvt ]    |   solo5-hvt guest, nested KVM
           |  eth1  :8080     |   sandbox subnet (no route out of the VPC)
           +--------+---------+
                    |
                 agent VM          reaches exactly one thing: eth1:8080
```

## What is closed, and by what

| Way out of the sandbox | Closed by |
|---|---|
| Direct internet | sandbox route table has only the `local` route; no NAT gateway, no VPC endpoints |
| DNS tunnelling via the Amazon resolver | VPC DNS support **off** (SGs and NACLs cannot filter that resolver) |
| Public DNS resolvers | no route; DHCP hands them out, but only the vend host can reach them |
| Other services on the vend host | `vend-sandbox` SG admits tcp/8080 only; host `INPUT` drops the rest |
| Using the vend host as a router | ENI source/dest check, the SG, and host `FORWARD` policy DROP |
| Credentials from instance metadata | no instance profile on either instance; IMDSv2, hop limit 1 |
| The rest of the VPC | agent SG egress is tcp/8080 to the vend ENI only; NACL on the sandbox subnet |
| **The vending machine itself** | the F\* URL gate (see the top-level README) |

On the host, the guest is further confined by `iptables`: it may open tcp/443
and tcp/853 to public addresses, and nothing to private, shared or link-local
space (so not IMDS, not the VPC). That layer is unverified and independent of
the proof, and it still holds even if the guest is fully compromised.

Operators get in through an **EC2 Instance Connect Endpoint**, which only
carries connections into the VPC.

## Requirements

* Terraform ≥ 1.6, AWS provider ≥ 6.68, AWS credentials, and the AWS CLI v2
  for `ec2-instance-connect ssh`.
* An instance type with **EC2 nested virtualization** for the host, because
  `solo5-hvt` needs `/dev/kvm`. The default is `m8i.large`; any C/M/R 7i or 8i
  type works, as does a `.metal` type.
* The host builds from `source_repo` at `source_ref` (default: this repository's `main`).
  To deploy unpushed changes, push a branch and set `source_ref` to it.

## Use

```bash
cd deploy/aws
terraform init
terraform apply                     # ~5 min, then the host builds for ~20-30 min
terraform output next_steps
```

The host builds `vend.hvt` natively on first boot with the repository's own
`make manifest && make unikernel`. Each deployment therefore gets a fresh
manifest signing key that never leaves the host. Docker is switched off once
the build is done. Watch it with:

```bash
$(terraform output -raw ssh_vend_host)
sudo tail -f /var/log/pvm-bootstrap.log      # finished when /opt/pvm/READY exists
journalctl -fu pvm-vend                      # the unikernel's console
```

Then, as the agent:

```bash
$(terraform output -raw ssh_agent)
escape-check                                 # every exit closed but one
bash /opt/pvm/replay.sh http://vend:8080     # the breach's exploit classes, replayed
vend status
vend fetch pypi pip requests urllib3 certifi charset-normalizer idna
python3 downloads/pip-*.whl/pip install --user --break-system-packages \
    --no-index --find-links=downloads requests
```

The agent image ships Python but not pip or Node. pip is on the allowlist so
an agent can bootstrap it through the machine: a wheel is a runnable zip.

## Cost and teardown

At the defaults this is roughly one `m8i.large`, one `t3.small`, an Elastic IP
and two small EBS volumes, about **$0.13/hour** in us-east-1. Instance Connect
Endpoints are free. There is no NAT gateway.

```bash
terraform destroy
```

## Files

| Path | Runs on | Purpose |
|---|---|---|
| `network.tf` | — | VPC, subnets, routes, DHCP options, NACL |
| `security.tf` | — | the four security groups |
| `instances.tf` | — | host (two ENIs, nested virt), agent, Instance Connect Endpoint |
| `host/pvm-bootstrap.sh` | host, once | build `vend.hvt`, extract the tender, disable Docker |
| `host/pvm-net.sh` | host, every boot | tap device, DNAT, guest egress policy |
| `host/pvm-vend.service` | host | `solo5-hvt` as an unprivileged user |
| `agent/vend` | agent | stdlib-only client: resolve, fetch, verify digests |
| `agent/escape-check` | agent | try every exit; exactly one should be open |
