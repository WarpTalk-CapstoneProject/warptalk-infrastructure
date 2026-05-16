output "public_ip" {
  description = "The public IP address of the WarpTalk server"
  value       = aws_instance.warptalk_server.public_ip
}

output "ssh_command" {
  description = "Command to SSH into the server"
  value       = "ssh -i \"${var.key_name}.pem\" ubuntu@${aws_instance.warptalk_server.public_ip}"
}

output "frontend_url" {
  description = "URL to access the WarpTalk frontend once deployed"
  value       = "http://${aws_instance.warptalk_server.public_ip}:3001"
}

output "api_gateway_url" {
  description = "URL to access the WarpTalk API Gateway"
  value       = "http://${aws_instance.warptalk_server.public_ip}:5200"
}
