output "web_instance_public_ip" {
  description = "Public IP address of the web EC2 instance"
  value       = aws_instance.web.public_ip
}
