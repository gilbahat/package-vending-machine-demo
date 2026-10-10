# Security groups. Terraform strips AWS's default allow-all egress rule from
# every group it creates, so a group with no egress rule below allows none.
#
#   eice          -> agent:22, vend-public:22        operator access only
#   agent         -> vend-sandbox:8080               and nothing else
#   vend-sandbox  <- agent:8080                      no egress at all
#   vend-public   -> internet 80/443 (host build), 443/853 (guest), 53 (host)

resource "aws_security_group" "eice" {
  name        = "${var.name}-eice"
  description = "EC2 Instance Connect Endpoint: SSH out to the two instances"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-eice" }
}

resource "aws_security_group" "agent" {
  name        = "${var.name}-agent"
  description = "Sandboxed agent: may talk to the vending machine and nothing else"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-agent" }
}

resource "aws_security_group" "vend_sandbox" {
  name        = "${var.name}-vend-sandbox"
  description = "Vending machine, agent-facing leg: tcp/8080 in from the agent"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-vend-sandbox" }
}

resource "aws_security_group" "vend_public" {
  name        = "${var.name}-vend-public"
  description = "Vending machine, upstream-facing leg"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-vend-public" }
}

# --- operator SSH via the Instance Connect Endpoint -------------------------

resource "aws_vpc_security_group_egress_rule" "eice_to_agent" {
  security_group_id            = aws_security_group.eice.id
  referenced_security_group_id = aws_security_group.agent.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
}

resource "aws_vpc_security_group_egress_rule" "eice_to_vend" {
  security_group_id            = aws_security_group.eice.id
  referenced_security_group_id = aws_security_group.vend_public.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
}

resource "aws_vpc_security_group_ingress_rule" "agent_ssh" {
  security_group_id            = aws_security_group.agent.id
  referenced_security_group_id = aws_security_group.eice.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
}

resource "aws_vpc_security_group_ingress_rule" "vend_ssh" {
  security_group_id            = aws_security_group.vend_public.id
  referenced_security_group_id = aws_security_group.eice.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
}

# --- the chokepoint ----------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "agent_to_vend" {
  security_group_id            = aws_security_group.agent.id
  referenced_security_group_id = aws_security_group.vend_sandbox.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_vpc_security_group_ingress_rule" "vend_from_agent" {
  security_group_id            = aws_security_group.vend_sandbox.id
  referenced_security_group_id = aws_security_group.agent.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

# --- upstream egress ---------------------------------------------------------
#
# 443: the guest's TLS to pypi.org / files.pythonhosted.org / npmjs.org, and
#      the host's one-time build (apt, git, opam, Docker Hub).
# 853: the guest resolves over DNS-over-TLS (mirage's default resolver).
# 80:  Ubuntu's EC2 apt mirrors.
# 53:  the host's own resolver traffic to var.upstream_resolvers.
#
# Which of these the *guest* may use is narrowed further by the host's
# iptables FORWARD policy: 443 and 853 only, never to private or link-local
# space.

resource "aws_vpc_security_group_egress_rule" "vend_tcp" {
  for_each = toset(["80", "443", "853", "53"])

  security_group_id = aws_security_group.vend_public.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
}

resource "aws_vpc_security_group_egress_rule" "vend_dns_udp" {
  for_each = toset(var.upstream_resolvers)

  security_group_id = aws_security_group.vend_public.id
  cidr_ipv4         = "${each.value}/32"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
}
