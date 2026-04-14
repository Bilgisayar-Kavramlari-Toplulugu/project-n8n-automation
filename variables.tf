variable "region" {
  description = "AWS bölgesi"
  type        = string
  default     = "eu-central-1"
}

variable "instance_type" {
  description = "EC2 instance tipi (daha hizli kurulum icin t3.small onerilir)"
  type        = string
  default     = "t3.small"
}

variable "use_spot_instance" {
  description = "Maliyeti dusurmek icin Spot Instance kullanilsin mi?"
  type        = bool
  default     = true
}

variable "key_name" {
  description = "AWS'de kayıtlı SSH Key Pair adı"
  type        = string
  default     = "my-key"
}

variable "public_key_path" {
  description = "Yerel SSH public key yolu"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "n8n_password" {
  description = "N8N arayüzü için şifre"
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.n8n_password)) >= 12 && trimspace(var.n8n_password) != "changeme123!"
    error_message = "n8n_password en az 12 karakter olmali ve tahmin edilebilir varsayilan parola kullanilmamali."
  }
}

variable "ssh_allowed_cidrs" {
  description = "SSH erişimi için izin verilen CIDR listesi. Boş bırakılırsa SSH açılmaz."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.ssh_allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "ssh_allowed_cidrs yalnızca geçerli CIDR blokları içermelidir."
  }
}

variable "ssh_public_key" {
  description = "Opsiyonel SSH public key content. SSH erişimi gerekiyorsa ssh_allowed_cidrs ile birlikte verin."
  type        = string
  default     = ""
}
