variable "region" {
  description = "AWS region. Must offer an instance type with nested virtualization (see vend_instance_type)."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefix for resource names and the Stack tag."
  type        = string
  default     = "pvm"
}

variable "vpc_cidr" {
  description = "CIDR of the whole VPC. The public and sandbox subnets are carved from it."
  type        = string
  default     = "10.42.0.0/16"
}

variable "availability_zone" {
  description = "AZ for both subnets. Empty picks the first AZ offering both instance types."
  type        = string
  default     = ""
}

variable "vend_instance_type" {
  description = <<-EOT
    Instance type for the vending machine host. solo5-hvt needs /dev/kvm, so
    this must support EC2 nested virtualization (C/M/R 7i and 8i families, at
    time of writing) or be a .metal type. 8 GiB is comfortable for the
    one-time native build of the unikernel.
  EOT
  type        = string
  default     = "m8i.large"
}

variable "agent_instance_type" {
  description = "Instance type for the sandboxed agent VM."
  type        = string
  default     = "t3.small"
}

variable "source_repo" {
  description = "Git repository the vending machine host clones and builds from."
  type        = string
  default     = "https://github.com/gilbahat/package-vending-machine-demo.git"
}

variable "source_ref" {
  description = "Branch or tag of source_repo to build."
  type        = string
  default     = "main"
}

variable "upstream_resolvers" {
  description = <<-EOT
    DNS resolvers handed out by DHCP. The VPC's own resolver is switched off
    (see network.tf), so these are only reachable from somewhere with a route
    to the internet -- i.e. the vending machine host, never the sandbox.
  EOT
  type        = list(string)
  default     = ["1.1.1.1", "9.9.9.9"]
}

variable "guest_mem_mb" {
  description = "Memory for the unikernel, in MiB. Artifacts are buffered whole, and the largest allowlisted wheels (scipy) are tens of MB."
  type        = number
  default     = 512
}
