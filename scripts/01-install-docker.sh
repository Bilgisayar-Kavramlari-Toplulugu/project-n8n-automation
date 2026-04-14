#!/bin/bash
exec > /var/log/01-install-docker.log 2>&1
echo "=== Docker Kurulumu Basliyor: $(date) ==="

# Ubuntu açılışında 'unattended-upgrades' ve 'apt-daily' servisleri
# apt kilitlerini tutabilir. Hata almamak için kilitlerin kalkmasını bekliyoruz.
echo "Apt kilitlerinin acilmasi bekleniyor... (1-3 dakika surebilir)"
export DEBIAN_FRONTEND=noninteractive

while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done;
while fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 5; done;
while fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do sleep 5; done;

# 1. Temel bagimliliklar
echo "Temel paketler kuruluyor..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

# 2. Docker resmi GPG anahtari
echo "Docker GPG anahtari ekleniyor..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# 3. Docker resmi apt repo
echo "Docker APT deposu tanımlanıyor..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Docker CE + Compose plugin kur
echo "Docker ve Docker Compose paketleri kuruluyor..."
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

echo "=== Docker Kurulumu Tamamlandi: $(date) ==="
