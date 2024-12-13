output "modelizeit_url" {
  value = "https://${aws_eip.instance_eip.public_ip}"
  description = "Access ModelizeIT Analyzer via HTTPS on Windows Server"
}
