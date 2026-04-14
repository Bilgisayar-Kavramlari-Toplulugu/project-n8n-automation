output "public_ip" {
  value       = aws_instance.app_server.public_ip
  description = "Makinenin Dinamik Public IP'si (Makine kapanıp açıldığında değişir)"
}

output "n8n_web_ui" {
  value       = "http://${aws_instance.app_server.public_ip}"
  description = "Caddy uzerinden N8N giris adresi"
}

output "ssh_command" {
  value = (
    length(var.ssh_allowed_cidrs) > 0 && trimspace(var.ssh_public_key) != ""
    ? "ssh ubuntu@${aws_instance.app_server.public_ip}"
    : "SSH disabled by default. Set ssh_public_key and ssh_allowed_cidrs to enable access."
  )
  description = "SSH bağlantı durumu"
}

output "caddy_status" {
  value       = "http://${aws_instance.app_server.public_ip} → Caddy reverse proxy çalışıyor"
  description = "HTTP üzerinden de N8N'e yönlendirme"
}
