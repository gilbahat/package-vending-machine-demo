locals {
  ssh = "aws ec2-instance-connect ssh --region ${var.region} --connection-type eice --os-user ubuntu --instance-id"
}

output "ssh_agent" {
  description = "Shell on the sandboxed agent VM."
  value       = "${local.ssh} ${aws_instance.agent.id}"
}

output "ssh_vend_host" {
  description = "Shell on the vending machine's host (for watching the build and the guest's log)."
  value       = "${local.ssh} ${aws_instance.vend.id}"
}

output "vend_url" {
  description = "The vending machine, as the agent sees it (also resolvable as http://vend:8080 on the agent)."
  value       = "http://${local.vend_sandbox_ip}:8080"
}

output "vend_public_ip" {
  description = "The host's upstream-facing address. Nothing listens on it."
  value       = aws_eip.vend.public_ip
}

output "next_steps" {
  description = "What to run once applied."
  value       = <<-EOT
    The host builds vend.hvt on first boot (~20-30 min). Follow it with:
      ${local.ssh} ${aws_instance.vend.id}
      sudo tail -f /var/log/pvm-bootstrap.log        # done when /opt/pvm/READY exists
      journalctl -fu pvm-vend                        # the guest's console

    Then, from the agent:
      ${local.ssh} ${aws_instance.agent.id}
      escape-check                                   # the vending machine is the only way out
      bash /opt/pvm/replay.sh http://vend:8080       # the breach's exploit classes
      vend fetch pypi pip requests urllib3 certifi charset-normalizer idna
      python3 downloads/pip-*.whl/pip install --user --break-system-packages \
          --no-index --find-links=downloads requests
  EOT
}
