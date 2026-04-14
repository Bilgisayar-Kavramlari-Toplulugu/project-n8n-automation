# 🔧 Özelleştirme & Güvenlik Rehberi

Bu döküman mevcut N8N + Caddy altyapısına eklenebilecek özellikleri, maliyet düşürme stratejilerini ve sunucu güvenlik sertleştirme (hardening) adımlarını kapsar.

---

## 📑 İçindekiler

- [Maliyet Düşürme](#-maliyet-düşürme)
- [Güvenlik Sertleştirme (Hardening)](#-güvenlik-sertleştirme-hardening)
- [Ağ Güvenliği (Terraform)](#-ağ-güvenliği-terraform-tarafı)
- [Eklenebilecek Özellikler](#-eklenebilecek-özellikler)
- [Hazır Kod Örnekleri](#-hazır-kod-örnekleri)

---

## 💰 Maliyet Düşürme

### 1. Spot Instance Kullanmak (~%70 tasarruf)

Spot instance, AWS'in boşta kalan kapasitesini ucuza satar. Kesintiye uğrayabilir ama N8N gibi kısa süreli workflow'lar için uygun.

```hcl
# main.tf — aws_instance bloğuna ekle:
resource "aws_instance" "app_server" {
  # ... mevcut ayarlar ...

  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price                      = "0.005"   # Saatlik max fiyat ($)
      spot_instance_type             = "persistent"
      instance_interruption_behavior = "stop"     # Kesintide durdur (silme)
    }
  }
}
```

| Tip | Saatlik | Aylık |
|-----|---------|-------|
| t3.micro On-Demand | $0.0116 | ~$8.50 |
| t3.micro Spot | ~$0.0035 | ~$2.50 |
| **Tasarruf** | | **~$6/ay (%70)** |

### 2. Daha Küçük Instance Tipi

```hcl
# variables.tf — t3.nano denemek için:
variable "instance_type" {
  default = "t3.nano"    # 2 vCPU, 0.5 GB RAM — en ucuz seçenek
}
```

| Instance | vCPU | RAM | Aylık |
|----------|------|-----|-------|
| t3.nano | 2 | 0.5 GB | ~$3.80 |
| t3.micro | 2 | 1 GB | ~$8.50 |
| t3.small | 2 | 2 GB | ~$17 |

> ⚠️ N8N + Caddy için minimum **1 GB RAM** (t3.micro) önerilir. t3.nano ile swap eklemen gerekir.

### 3. Swap Alanı Eklemek (Düşük RAM'i telafi eder)

`scripts/user-data.sh` dosyasına ekle:

```bash
# Swap alanı oluştur (2 GB)
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

### 4. Elastic IP — Boşta Bırakma!

Elastic IP **kullanımdayken** ücretsiz, **boşta** bırakırsan saatlik ücret keser (~$3.65/ay). Instance'ı sileceksen Elastic IP'yi de sil:

```bash
terraform destroy   # Her ikisini de siler ✓
```

### 5. Free Tier'dan Maksimum Faydalanma

AWS Free Tier (ilk 12 ay):
- **750 saat/ay** t2.micro veya t3.micro
- **30 GB** EBS depolama
- **15 GB** data transfer out

```hcl
# Free Tier uyumlu ayarlar:
variable "instance_type" {
  default = "t3.micro"
}
```

### 6. Otomatik Başlat/Durdur (Zamanlayıcı)

Eğer N8N'i sadece mesai saatlerinde kullanıyorsan, AWS Lambda + CloudWatch ile otomatik durdurma yapabilirsin:

```hcl
# Gelecekte eklenebilir:
# - EventBridge rule ile her gece 22:00'de durdur
# - Her sabah 08:00'de başlat
# - Aylık maliyet ~%50 düşer
```

---

## 🔒 Güvenlik Sertleştirme (Hardening)

### user-data.sh'ye Eklenecek Güvenlik Adımları

Aşağıdaki blokların tamamını `scripts/user-data.sh` dosyasında Docker kurulumundan **sonra**, stack başlatmadan **önce** eklemen önerilir.

---

### 1. SSH Sertleştirme

```bash
# ──────────────────────────────────────
# SSH HARDENING
# ──────────────────────────────────────

# Root ile SSH girişini kapat
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# Parola ile girişi kapat (sadece SSH key ile giriş)
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

# Boş parolaya izin verme
sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config

# X11 forwarding kapat (gerek yok)
sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config

# Max authentication deneme sayısı
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config

# SSH oturum zaman aşımı (5 dakika boşta → bağlantı düşer)
sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 2/' /etc/ssh/sshd_config

# SSH servisini yeniden başlat
systemctl restart sshd
```

**Sonuç:**
| Ayar | Önce | Sonra |
|------|------|-------|
| Root SSH girişi | ✅ Açık | ❌ Kapalı |
| Parola ile giriş | ✅ Açık | ❌ Kapalı (sadece key) |
| Boş parola | ✅ Mümkün | ❌ Kapalı |
| Max deneme | 6 | 3 |
| Boşta timeout | ∞ | 5 dk |

---

### 2. Otomatik Güvenlik Güncellemeleri

```bash
# ──────────────────────────────────────
# OTOMATIK GÜNCELLEMELER
# ──────────────────────────────────────
apt-get install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTOEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTOEOF
```

---

### 3. Fail2Ban (Brute Force Koruması)

```bash
# ──────────────────────────────────────
# FAIL2BAN — SSH brute force koruması
# ──────────────────────────────────────
apt-get install -y fail2ban

cat > /etc/fail2ban/jail.local << 'F2BEOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = systemd
F2BEOF

systemctl enable fail2ban
systemctl start fail2ban
```

**Sonuç:** 10 dakika içinde 3 başarısız SSH denemesi → IP 1 saat yasaklanır.

---

### 4. UFW Firewall (Ekstra Katman)

```bash
# ──────────────────────────────────────
# UFW FIREWALL — OS seviyesinde ekstra güvenlik
# ──────────────────────────────────────
apt-get install -y ufw

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp     # SSH
ufw allow 80/tcp     # HTTP
ufw allow 443/tcp    # HTTPS
ufw allow 5678/tcp   # N8N (bunu kaldırabilirsin, Caddy üzerinden erişirsin)
ufw --force enable
```

> 💡 **İpucu:** Eğer Caddy üzerinden N8N'e erişiyorsan, `5678` portunu UFW'den ve Security Group'tan kaldırabilirsin. Böylece N8N'e sadece Caddy üzerinden erişilir.

---

### 5. Root Hesabını Tamamen Kilitle

```bash
# ──────────────────────────────────────
# ROOT HESABINI KİLİTLE
# ──────────────────────────────────────
passwd -l root            # root parolasını kilitle
usermod -s /usr/sbin/nologin root   # root shell'i kapat
```

---

### 6. Sistem Loglarını İzle

```bash
# ──────────────────────────────────────
# LOG İZLEME
# ──────────────────────────────────────
# Journald loglarını kalıcı yap
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal
systemctl restart systemd-journald

# Auth loglarını izleyecek cron job
cat > /etc/cron.daily/check-auth << 'CRONEOF'
#!/bin/bash
echo "=== SSH Login Denemeleri (Son 24 saat) ===" > /var/log/auth-report.log
journalctl -u sshd --since "24 hours ago" --no-pager >> /var/log/auth-report.log
CRONEOF
chmod +x /etc/cron.daily/check-auth
```

---

## 🌐 Ağ Güvenliği (Terraform Tarafı)

### 1. SSH'ı Sadece Kendi IP'ne Aç

**En önemli adım!** SSH'ı tüm dünyaya (`0.0.0.0/0`) açmak yerine sadece kendi IP'nden eriş:

```hcl
# variables.tf — ekle:
variable "my_ip" {
  description = "SSH erişimi için izin verilen IP (CIDR formatı)"
  type        = string
  default     = "0.0.0.0/0"   # terraform apply -var="my_ip=85.110.XX.XX/32"
}
```

```hcl
# main.tf — SSH ingress kuralını değiştir:
ingress {
  description = "SSH - sadece benim IP'im"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [var.my_ip]    # ← kendi IP'ni ver
}
```

```bash
# Kullanım:
terraform apply -var="my_ip=$(curl -s ifconfig.me)/32"
```

### 2. N8N Portunu Kapat (Caddy Üzerinden Eriş)

N8N'e doğrudan `:5678` üzerinden erişmeye gerek yok, Caddy `:80` üzerinden yönlendiriyor:

```hcl
# main.tf — bu ingress bloğunu SİL veya yoruma al:
# ingress {
#   description = "N8N Web UI"
#   from_port   = 5678
#   to_port     = 5678
#   protocol    = "tcp"
#   cidr_blocks = ["0.0.0.0/0"]
# }
```

### 3. Egress Kurallarını Kısıtla

Şu an sunucu dışarıya her yere erişebilir. Bunu kısıtlayabilirsin:

```hcl
# Sadece HTTP/HTTPS ve DNS çıkışına izin ver:
egress {
  description = "HTTPS out"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

egress {
  description = "HTTP out"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

egress {
  description = "DNS"
  from_port   = 53
  to_port     = 53
  protocol    = "udp"
  cidr_blocks = ["0.0.0.0/0"]
}
```

---

## 🧩 Eklenebilecek Özellikler

### Kolay (1-2 satır değişiklik)

| Özellik | Nasıl? | Etki |
|---------|--------|------|
| **Domain bağlama** | Caddyfile'da `:80` yerine `n8n.example.com` yaz | Otomatik SSL sertifikası |
| **N8N şifresini değiştir** | `terraform apply -var="n8n_password=YeniSifre"` | Daha güvenli giriş |
| **Farklı region** | `terraform apply -var="region=us-east-1"` | Farklı lokasyon |
| **Instance büyütme** | `terraform apply -var="instance_type=t3.small"` | Daha fazla RAM |

### Orta (Yeni dosya/blok ekleme)

| Özellik | Açıklama |
|---------|----------|
| **S3 Backend** | `terraform.tfstate` dosyasını S3'te sakla, takım çalışması için |
| **CloudWatch Alarm** | CPU %80+ olunca e-posta uyarısı |
| **SNS Bildirimi** | Sunucu kapanırsa bildirim gönder |
| **Otomatik Yedekleme** | N8N data volume'unu S3'e yedekle (cron) |
| **EBS Snapshot** | Disk snapshot'ı zamanlayıcıyla al |

### Gelişmiş (Mimari değişiklik)

| Özellik | Açıklama |
|---------|----------|
| **ALB + Auto Scaling** | Yük dengeleyici + otomatik ölçekleme (N8N burada sınırlı) |
| **RDS PostgreSQL** | N8N'in SQLite yerine gerçek veritabanı kullanması |
| **Terraform Cloud** | Remote state + plan approval workflow |
| **WAF** | Web Application Firewall — DDoS ve kötü bot koruması |
| **VPN / Bastion Host** | SSH'ı tamamen kapatıp VPN üzerinden erişim |

---

## 📋 Hazır Kod Örnekleri

### A. Domain ile Otomatik SSL

`scripts/user-data.sh` içindeki Caddyfile bölümünü değiştir:

```bash
cat > /opt/stack/Caddyfile << 'CADDYEOF'
n8n.senin-domain.com {
    reverse_proxy n8n:5678
}
CADDYEOF
```

Caddy otomatik olarak Let's Encrypt SSL sertifikası alır. Ekstra bir şey yapmana gerek yok.

> ⚠️ Domain'in DNS kaydında A record olarak Elastic IP'yi göstermen lazım.

---

### B. S3 Remote State (Takım çalışması)

```hcl
# main.tf — terraform bloğunu güncelle:
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "terraform-state-bucket-HESAP_ID"
    key    = "n8n/terraform.tfstate"
    region = "eu-central-1"
  }
}
```

---

### C. N8N Verileri S3'e Otomatik Yedekle

`scripts/user-data.sh` sonuna ekle:

```bash
# Her gece 03:00'de N8N verilerini S3'e yedekle
cat > /etc/cron.d/n8n-backup << 'BACKUPEOF'
0 3 * * * root docker run --rm \
  -v n8n_data:/data \
  -v /tmp/backup:/backup \
  alpine tar czf /backup/n8n-$(date +\%Y\%m\%d).tar.gz /data \
  && aws s3 cp /tmp/backup/ s3://my-backup-bucket/n8n/ --recursive \
  && rm -rf /tmp/backup/*
BACKUPEOF
```

> ⚠️ EC2'ye S3 yazma izni için IAM Instance Profile (role) eklenmeli.

---

### D. CloudWatch CPU Alarmı

```hcl
# main.tf — sonuna ekle:
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "n8n-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU %80 üzeri - N8N sunucu yüklenmiş olabilir"

  dimensions = {
    InstanceId = aws_instance.app_server.id
  }

  # alarm_actions = [aws_sns_topic.alerts.arn]  # SNS ile e-posta
}
```

---

## ✅ Önerilen Uygulama Sırası

Aşağıda hangi iyileştirmeleri hangi sırayla uygulamanı öneriyoruz:

### Öncelik 1 — Hemen Yap (Güvenlik)

```
☐ SSH root girişini kapat (PermitRootLogin no)
☐ Parola ile girişi kapat (PasswordAuthentication no)
☐ Fail2Ban kur
☐ SSH'ı sadece kendi IP'ne aç (Security Group)
☐ N8N 5678 portunu kapat (Caddy üzerinden eriş)
```

### Öncelik 2 — Bu Hafta (Maliyet + Güvenlik)

```
☐ Swap alanı ekle (RAM yetersizse)
☐ Otomatik güvenlik güncellemeleri (unattended-upgrades)
☐ UFW firewall aktifleştir
☐ Root hesabını tamamen kilitle
☐ N8N şifresini güçlü yap
```

### Öncelik 3 — Bu Ay (Özellikler)

```
☐ Domain bağla + SSL (Caddy otomatik yapar)
☐ S3 remote state
☐ Otomatik yedekleme (S3)
☐ CloudWatch alarmları
```

### Öncelik 4 — İstersen (İleri Seviye)

```
☐ Spot instance dene
☐ Bastion host / VPN
☐ RDS PostgreSQL
☐ WAF koruması
```
