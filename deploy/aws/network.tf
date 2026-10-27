# The network, built to reproduce the shape of the July 2026 escape:
#
#                  internet
#                     |
#            +--------+---------+   public subnet (IGW route)
#            |  eth0  (EIP)     |   guest egress: tcp/443, tcp/853 only
#            |                  |
#            |  [ vend.hvt ]    |   solo5-hvt guest on a tap, NAT'd by host
#            |                  |
#            |  eth1  :8080     |   sandbox subnet (no route out of the VPC)
#            +--------+---------+
#                     |
#                  agent VM         reaches exactly one thing: eth1:8080
#
# The sandbox subnet's route table has only the implicit `local` route. There
# is no NAT gateway and no VPC endpoint in this VPC: the vending machine is the
# only chokepoint, which is precisely the property the escape relied on.

data "aws_ec2_instance_type_offerings" "this" {
  for_each      = toset([var.vend_instance_type, var.agent_instance_type])
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [each.value]
  }
}

locals {
  # Both subnets share one AZ, so it must offer both instance types.
  az = var.availability_zone != "" ? var.availability_zone : sort(setintersection(
    data.aws_ec2_instance_type_offerings.this[var.vend_instance_type].locations,
    data.aws_ec2_instance_type_offerings.this[var.agent_instance_type].locations,
  ))[0]

  public_cidr  = cidrsubnet(var.vpc_cidr, 8, 0)
  sandbox_cidr = cidrsubnet(var.vpc_cidr, 8, 1)

  # Fixed so the agent's /etc/hosts and the NACL can name it before boot.
  vend_sandbox_ip = cidrhost(local.sandbox_cidr, 10)
}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # The Amazon-provided resolver (VPC+2 and 169.254.169.253) answers every
  # instance in the VPC and is not filtered by security groups or NACLs. A
  # recursive resolver reachable from the sandbox is a DNS-tunnelling exit
  # that bypasses the chokepoint entirely, so it is switched off. Instances
  # that need DNS get public resolvers via DHCP, which only the vending
  # machine host has a route to.
  enable_dns_support   = false
  enable_dns_hostnames = false

  tags = { Name = "${var.name}-vpc" }
}

resource "aws_vpc_dhcp_options" "this" {
  domain_name_servers = var.upstream_resolvers
  tags                = { Name = "${var.name}-dhcp" }
}

resource "aws_vpc_dhcp_options_association" "this" {
  vpc_id          = aws_vpc.this.id
  dhcp_options_id = aws_vpc_dhcp_options.this.id
}

# ---------------------------------------------------------------------------
# Public subnet: the vending machine's upstream-facing leg, and the EC2
# Instance Connect Endpoint operators use to reach both instances.
# ---------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.public_cidr
  availability_zone = local.az
  tags              = { Name = "${var.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-public" }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Sandbox subnet: the agent, and the vending machine's agent-facing leg.
# ---------------------------------------------------------------------------

resource "aws_subnet" "sandbox" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.sandbox_cidr
  availability_zone = local.az
  tags              = { Name = "${var.name}-sandbox" }
}

# Deliberately no routes: only the implicit `local` one.
resource "aws_route_table" "sandbox" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-sandbox-no-egress" }
}

resource "aws_route_table_association" "sandbox" {
  subnet_id      = aws_subnet.sandbox.id
  route_table_id = aws_route_table.sandbox.id
}

# Belt and braces under the security groups. NACLs only see traffic crossing
# the subnet boundary, so agent <-> vend eth1 (same subnet) is governed by the
# security groups alone; what this pins down is that nothing leaves the
# sandbox subnet for the rest of the VPC except SSH replies to the Instance
# Connect Endpoint.
resource "aws_network_acl" "sandbox" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [aws_subnet.sandbox.id]

  ingress {
    rule_no    = 100
    action     = "allow"
    protocol   = "tcp"
    cidr_block = local.public_cidr
    from_port  = 22
    to_port    = 22
  }

  egress {
    rule_no    = 100
    action     = "allow"
    protocol   = "tcp"
    cidr_block = local.public_cidr
    from_port  = 1024
    to_port    = 65535
  }

  tags = { Name = "${var.name}-sandbox" }
}
