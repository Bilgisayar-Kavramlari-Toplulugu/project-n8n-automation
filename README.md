# ☁️ N8N + Caddy — AWS Terraform Otomasyonu (v2 - GitHub Actions)

Bu proje, AWS üzerinde **N8N** ve **Caddy** stack'ini tamamen otomize edilmiş, güvenli ve maliyet odaklı bir şekilde kurmanızı sağlar. Yeni sürümle birlikte yerel kurulumun yanı sıra **GitHub Actions** üzerinden tam otomasyon ve **OIDC (Keyless)** güvenliği eklenmiştir.

---

## 📁 Yeni Proje Yapısı

```
local-terraform/
├── bootstrap/           # Bir kerelik çalıştırılan S3 State + OIDC kurulumu
├── .github/workflows/   # GitHub Actions otomasyon dosyaları (CI/CD)
├── scripts/             # Modüler kurulum scriptleri
│   ├── 00-setup-swap.sh # RAM optimizasyonu (2GB Swap)
│   ├── 01-install-docker.sh
│   ├── 02-deploy-stack.sh
│   └── 03-security-hardening.sh # UFW, Fail2Ban, SSH Hardening
├── main.tf              # Ana altyapı (Spot Instance, OIDC entegrasyonu)
├── variables.tf         # t3.small, Spot Instance ve SSH Key ayarları
└── outputs.tf           # Dinamik IP ve SSH komutları
```

---

## 🚀 Öne Çıkan Özellikler

- **GitHub Actions Entegrasyonu:** Kodunuzu pushladığınızda otomatik `apply`, PR açtığınızda `plan`.
- **Sıfır Key Güvenliği (OIDC):** GitHub Secrets'te AWS Access Key saklamanıza gerek yok. IAM Role geçici izinlerle çalışır.
- **Maliyet Odaklı (Spot + No Elastic IP):** Spot Instance kullanarak %70 tasarruf sağlanır. Elastic IP maliyetinden kaçınmak için Dinamik IP kullanılır.
- **Güvenlik (Hardening):** fail2ban, UFW, SSH parola girişinin kapatılması ve N8N'in yalnızca Caddy arkasından yayınlanması otomatik yapılır.
- **Performans:** 1GB RAM'li makinelerde donmayı engellemek için 2GB otomatik Swap alanı.

---

## 🛠️ Kurulum ve Devreye Alma

### 1. Hazırlık (Bootstrap)
Terraform state dosyalarını bulutta saklamak ve GitHub'a izin vermek için bir kez yerelinizde çalıştırın:
```bash
cd bootstrap
# github_repo için repo hazir degilse gecici olarak "ORG/*" kullanabilirsiniz.
# Repo olusunca bunu mutlaka "ORG/REPO" seviyesine daraltin.
terraform init
terraform apply
```
*Çıktıdaki `github_role_arn` değerini GitHub Secrets'a ekleyeceksiniz.*

### 2. State Migration
Yarattığınız S3 bucket'ını kullanmaya başlamak için ana dizinde:
```bash
terraform init -migrate-state -reconfigure
```

## 🔐 AWS Console: Manuel Yapılması Gerekenler

Bootstrap aşamasında veya sonrasında bazı işlemleri AWS Console üzerinden yapmanız gerekebilir. Özellike `AccessDenied` hatası alıyorsanız buraya dikkat:

### 1. IAM Kullanıcı Yetkilerini Düzeltme (Least Privilege)
Eğer `bootstrap` klasöründe `terraform apply` yaparken **"AccessDenied"** hatası alıyorsanız, elinizdeki yerel anahtarların IAM kaynağı yaratma yetkisi yok demektir. Güvenlik gereği Admin yetkisi vermek yerine, sadece şu dar kapsamlı **"Bootstrap Policy"** JSON'ını kullanıcınıza (Inline Policy olarak) ekleyin:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "saml:CreateOpenIDConnectProvider",
                "iam:CreateOpenIDConnectProvider",
                "iam:GetOpenIDConnectProvider",
                "iam:DeleteOpenIDConnectProvider",
                "iam:CreateRole",
                "iam:GetRole",
                "iam:DeleteRole",
                "iam:PutRolePolicy",
                "iam:GetRolePolicy",
                "iam:DeleteRolePolicy",
                "s3:CreateBucket",
                "s3:PutBucketVersioning",
                "s3:GetBucket*",
                "s3:ListBucket",
                "dynamodb:CreateTable",
                "dynamodb:DescribeTable",
                "dynamodb:DeleteTable"
            ],
            "Resource": "*"
        }
    ]
}
```
**NOT:** Bootstrap bittikten sonra bu yerel kullanıcıyı silebilir veya anahtarlarını deaktive edebilirsiniz. Artık her şey OIDC üzerinden (anahtarsız) GitHub tarafından yönetilecek.

### 2. OIDC Rolünü ve ARN'ı Bulma
Bootstrap bittikten sonra GitHub Action'a vermeniz gereken `ROLE_ARN` bilgisini kaybetmediyseniz:
1.  **IAM** > **Roles** kısmına gidin.
2.  `GitHubTerraformExecutionRole` isimli rolü arayın.
3.  Rolün içine girince en üstte yazan **ARN** değerini kopyalayıp GitHub Secrets'a (Adım 3) ekleyin.

### 3. GitHub Secrets
GitHub reponuzun ayarlarına şu secret'ları ekleyin:
- `AWS_ROLE_ARN`: Bootstrap çıktısındaki Role ARN.
- `N8N_PASSWORD`: N8N basic auth için güçlü bir parola.
- `SSH_PUBLIC_KEY`: Opsiyonel. Makineye SSH ile bağlanmak istiyorsanız public key içeriği.
- `SSH_ALLOWED_CIDRS`: Opsiyonel. JSON dizi formatında CIDR listesi. Örn: `["85.105.10.20/32"]`

SSH erişimi varsayılan olarak kapalıdır. `SSH_PUBLIC_KEY` ve `SSH_ALLOWED_CIDRS` birlikte verilirse yalnızca belirttiğiniz IP'lere açılır.

`github_repo = "ORG/*"` geçici olarak çalışır; ancak bu durumda ilgili role'i assume edebilen kapsam tek repo değil organizasyondaki tüm uygun repolar olur. Repo hazır olduğunda bunu `ORG/REPO` seviyesine daraltın.

---

## 🔄 Otomasyon Akışı

1. **Pull Request:** Herhangi bir branştan `main`'e PR açtığınızda `terraform plan` çalışır ve sonuç PR altına yorum olarak yazılır.
2. **Merge (Push to Main):** Kod `main` branşında birleştiği an `terraform apply` tetiklenir ve sunucu güncellenir.
3. **Manual Destroy:** İhtiyaç duyduğunuzda GitHub Actions panelinden "Terraform Destroy" workflow'unu manuel çalıştırarak her şeyi silebilirsiniz.

---

## 🏗️ Altyapı Detayları

| Özellik | Detay |
|---------|-------|
| **Bölge** | `eu-central-1` (Frankfurt) |
| **Instance** | `t3.small` (Önerilen) |
| **Market** | Spot (Persistent / Stop behavior) |
| **İşletim Sistemi** | Ubuntu 22.04 LTS |
| **Güvenlik** | OIDC, UFW, fail2ban, Caddy-only N8N exposure |

### 🔒 Açık Portlar
- **22 (SSH):** Varsayılan olarak kapalıdır; yalnızca `ssh_allowed_cidrs` tanımlanırsa açılır.
- **80/443 (Web):** Caddy Reverse Proxy.

---

## 💰 Maliyet Tahmini (Spot + t3.small)

- **t3.small (Spot):** ~$4-6 / ay (Normal fiyatın ~%70 altı)
- **S3 & DynamoDB:** ~$0.01 / ay (Yalnızca kullanım kadar)
- **Elastic IP:** $0 (Kullanılmıyor, Dinamik IP tercih edildi)
- **Toplam Tahmini:** **~$5-7 / ay** (Performanslı n8n için en ucuz çözüm)

---

## ❓ Yardım ve Destek
Sunucuya bağlandığınızda kurulum loglarını şu komutla izleyebilirsiniz:
`tail -f /var/log/02-deploy-stack.log`
