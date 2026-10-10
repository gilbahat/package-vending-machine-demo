data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

locals {
  # The guest's private link to the host. Only the host ever sees it.
  guest_gw = "192.168.100.1"
  guest_ip = "192.168.100.2"

  imds = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1 # a NAT'd guest is one hop too far
  }
}

# ===========================================================================
# The vending machine host: two legs, one per subnet.
# ===========================================================================

resource "aws_network_interface" "vend_public" {
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.vend_public.id]
  description     = "vending machine: upstream-facing"
  tags            = { Name = "${var.name}-vend-public" }
}

resource "aws_eip" "vend" {
  domain            = "vpc"
  network_interface = aws_network_interface.vend_public.id
  depends_on        = [aws_internet_gateway.this]
  tags              = { Name = "${var.name}-vend" }
}

resource "aws_network_interface" "vend_sandbox" {
  subnet_id       = aws_subnet.sandbox.id
  private_ips     = [local.vend_sandbox_ip]
  security_groups = [aws_security_group.vend_sandbox.id]
  description     = "vending machine: agent-facing"
  # Left on deliberately: the ENI drops anything not addressed to it, so the
  # agent cannot use the host as a router even if the host's firewall failed.
  source_dest_check = true
  tags              = { Name = "${var.name}-vend-sandbox" }
}

locals {
  vend_env = <<-EOT
    SANDBOX_MAC=${lower(aws_network_interface.vend_sandbox.mac_address)}
    SANDBOX_IP=${local.vend_sandbox_ip}
    SANDBOX_PREFIX=${split("/", local.sandbox_cidr)[1]}
    GUEST_IP=${local.guest_ip}
    GUEST_GW=${local.guest_gw}
    GUEST_MEM_MB=${var.guest_mem_mb}
    SOURCE_REPO=${var.source_repo}
    SOURCE_REF=${var.source_ref}
  EOT

  vend_user_data = "#cloud-config\n${yamlencode({
    write_files = [
      { path = "/etc/pvm.env", permissions = "0644", content = local.vend_env },
      { path = "/usr/local/sbin/pvm-bootstrap.sh", permissions = "0755", content = file("${path.module}/host/pvm-bootstrap.sh") },
      { path = "/usr/local/sbin/pvm-net.sh", permissions = "0755", content = file("${path.module}/host/pvm-net.sh") },
      { path = "/etc/systemd/system/pvm-net.service", permissions = "0644", content = file("${path.module}/host/pvm-net.service") },
      { path = "/etc/systemd/system/pvm-vend.service", permissions = "0644", content = file("${path.module}/host/pvm-vend.service") },
    ]
    runcmd = [["/usr/local/sbin/pvm-bootstrap.sh"]]
  })}"
}

resource "aws_instance" "vend" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.vend_instance_type

  # solo5-hvt is a KVM tender; this is what makes /dev/kvm appear.
  cpu_options {
    nested_virtualization = "enabled"
  }

  primary_network_interface {
    network_interface_id = aws_network_interface.vend_public.id
  }

  metadata_options {
    http_endpoint               = local.imds.http_endpoint
    http_tokens                 = local.imds.http_tokens
    http_put_response_hop_limit = local.imds.http_put_response_hop_limit
  }

  root_block_device {
    volume_size = 30 # the build image is several GB
    volume_type = "gp3"
    encrypted   = true
  }

  user_data_base64            = base64gzip(local.vend_user_data)
  user_data_replace_on_change = true

  # Resolvers and the public address must exist before first boot: the
  # bootstrap starts downloading immediately.
  depends_on = [
    aws_eip.vend,
    aws_route.public_default,
    aws_vpc_dhcp_options_association.this,
  ]

  tags = { Name = "${var.name}-vend" }
}

# Attached after launch; pvm-bootstrap.sh waits for it to appear.
resource "aws_network_interface_attachment" "vend_sandbox" {
  instance_id          = aws_instance.vend.id
  network_interface_id = aws_network_interface.vend_sandbox.id
  device_index         = 1
}

# ===========================================================================
# The agent: no public IP, no route out, no IAM role, nothing to steal.
# ===========================================================================

locals {
  agent_user_data = "#cloud-config\n${yamlencode({
    write_files = [
      { path = "/usr/local/bin/vend", permissions = "0755", content = file("${path.module}/agent/vend") },
      { path = "/usr/local/bin/escape-check", permissions = "0755", content = file("${path.module}/agent/escape-check") },
      { path = "/opt/pvm/replay.sh", permissions = "0755", content = file("${path.module}/../../attack/replay.sh") },
      { path = "/etc/pvm-agent.env", permissions = "0644", content = "VPC_DNS=${cidrhost(var.vpc_cidr, 2)}\n" },
    ]
    runcmd = [
      ["sh", "-c", "grep -q ' vend$' /etc/hosts || echo '${local.vend_sandbox_ip} vend' >> /etc/hosts"],
    ]
  })}"
}

resource "aws_instance" "agent" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.agent_instance_type
  subnet_id                   = aws_subnet.sandbox.id
  vpc_security_group_ids      = [aws_security_group.agent.id]
  associate_public_ip_address = false

  metadata_options {
    http_endpoint               = local.imds.http_endpoint
    http_tokens                 = local.imds.http_tokens
    http_put_response_hop_limit = local.imds.http_put_response_hop_limit
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  user_data_base64            = base64gzip(local.agent_user_data)
  user_data_replace_on_change = true

  depends_on = [aws_vpc_dhcp_options_association.this]

  tags = { Name = "${var.name}-agent" }
}

# ===========================================================================
# Operator access. An Instance Connect Endpoint only carries connections
# *into* the VPC, so it gives the sandbox no way out.
# ===========================================================================

resource "aws_ec2_instance_connect_endpoint" "this" {
  subnet_id          = aws_subnet.public.id
  security_group_ids = [aws_security_group.eice.id]
  preserve_client_ip = false
  tags               = { Name = "${var.name}-eice" }
}
