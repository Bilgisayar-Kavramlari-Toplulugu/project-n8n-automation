#!/bin/bash
exec > /var/log/03-security-hardening.log 2>&1
echo "=== Guvenlik Sikilastirmasi (Hardening) Basliyor: $(date) ==="

# 1. Gerekli güvenlik paketlerini kur
export DEBIAN_FRONTEND=noninteractive
apt-get install -y fail2ban ufw unattended-upgrades

# 2. UFW (Güvenlik Duvarı - Uncomplicated Firewall)
# AWS Security Group dışında sunucu içinde de ekstra güvenlik katmanı oluşturur
ufw default deny incoming
ufw default allow outgoing
%{ if enable_ssh ~}
ufw allow 22/tcp      # SSH
%{ endif ~}
ufw allow 80/tcp      # HTTP (Caddy)
ufw allow 443/tcp     # HTTPS (Caddy)
ufw --force enable

# 3. Fail2ban Yapılandırması (Brute-force SSH saldırılarını engellemek için)
# Eğer bir IP 3 kez yanlış giriş yaparsa, o ipyi 1 saat boyunca banlar!
cat > /etc/fail2ban/jail.local << 'FAILEOF'
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
FAILEOF

systemctl restart fail2ban
systemctl enable fail2ban

# 4. SSH Hardening
# Root girişi ve parola ile giriş tamamen kapatılıyor (Sadece SSH Key kabul edilir)
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
# Boşta kalan (inaktif) SSH bağlantılarını 10 dakika sonra düşürme ayarı
echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
echo "ClientAliveCountMax 2" >> /etc/ssh/sshd_config

systemctl restart sshd

# 5. Otomatik Güvenlik Güncellemeleri
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "=== Guvenlik Sikilastirmasi Tamamlandi: $(date) ==="
