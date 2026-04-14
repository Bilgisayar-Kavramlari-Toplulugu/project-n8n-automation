#!/bin/bash
exec > /var/log/02-deploy-stack.log 2>&1
echo "=== N8N & Caddy Stack Kurulumu Basliyor: $(date) ==="

# 1. Docker servisi ayakta mı kontrol et
echo "Docker daemon'in hazir olmasi bekleniyor..."
while ! docker info >/dev/null 2>&1; do
    echo "Docker hazir degil, 5 saniye bekleniyor..."
    sleep 5
done

# 2. Stack dizini olustur
echo "/opt/stack dizini olusturuluyor..."
mkdir -p /opt/stack

# 3. Caddy konfig (port 80 -> N8N:5678)
echo "Caddyfile olusturuluyor..."
cat > /opt/stack/Caddyfile << 'CADDYEOF'
:80 {
    reverse_proxy n8n:5678
}
CADDYEOF

# 4. Docker Compose
echo "docker-compose.yml olusturuluyor..."
cat > /opt/stack/docker-compose.yml << 'COMPOSEEOF'
version: "3.8"

services:
  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/stack/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - stack_net
    depends_on:
      - n8n

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: always
    environment:
      N8N_BASIC_AUTH_ACTIVE: "true"
      N8N_BASIC_AUTH_USER: "admin"
      N8N_BASIC_AUTH_PASSWORD: ${n8n_password}
      GENERIC_TIMEZONE: "Europe/Istanbul"
      N8N_PROTOCOL: "http"
      N8N_SECURE_COOKIE: "false"
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - stack_net

volumes:
  caddy_data:
  caddy_config:
  n8n_data:

networks:
  stack_net:
    driver: bridge
COMPOSEEOF

# 5. Stack'i baslat
echo "Docker Compose ile servisler ayaga kaldiriliyor..."
cd /opt/stack
docker compose up -d

echo "=== Stack Kurulumu Tamamlandi: $(date) ==="
