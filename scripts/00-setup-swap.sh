#!/bin/bash
exec > /var/log/00-setup-swap.log 2>&1
echo "=== Swap Dosyasi Kurulumu Basliyor: $(date) ==="

# 2GB'lık bir swap (sanal bellek) dosyası oluşturuyoruz
# N8N gibi Node.js uygulamaları ağır çalışabildiği için t3.micro cihazın ram'ini çok doldurursa OOM yememek için kritik!

if grep -q "swapfile" /etc/fstab; then
    echo "Swap zaten fstab icerisinde tanimli. Atliyor..."
else
    echo "2GB Swap dosyasi olusturuluyor..."
    # fallocate diski hızlıca ayırır
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    # Makine açılıp kapandığında (reboot) swap'in tekrar aktif olması için fstab'a ekliyoruz
    echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab

    # Swap kullanım alışkanlığı ayarları
    # vm.swappiness: Ram tam dolmadan swap'e geçmeyi engeller (daha performanslı)
    sysctl vm.swappiness=10
    sysctl vm.vfs_cache_pressure=50
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
fi

echo "=== Swap Dosyasi Kurulumu Tamamlandi: $(date) ==="
