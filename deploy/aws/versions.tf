terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # cpu_options.nested_virtualization arrived in the 6.x line.
      version = "~> 6.68"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "package-vending-machine-demo"
      Stack   = var.name
    }
  }
}
