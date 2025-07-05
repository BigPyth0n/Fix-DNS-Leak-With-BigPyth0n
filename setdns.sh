#!/bin/bash

# رنگ‌ها
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # بدون رنگ

# آدرس‌های DNS ترکیه‌ای (قابل تغییر)
DNS1="193.192.98.66"  # Turk Telekom
DNS2="212.156.4.20"   # Turk Telekom

echo -e "${BLUE}🔧 نصب resolvconf (در صورت نیاز)...${NC}"
sudo apt update -y && sudo apt install -y resolvconf

echo -e "${BLUE}🔧 تنظیم DNS در resolvconf...${NC}"
sudo bash -c "echo -e 'nameserver $DNS1\nnameserver $DNS2' > /etc/resolvconf/resolv.conf.d/base"
sudo resolvconf -u

echo -e "${BLUE}🔧 تنظیم systemd-resolved...${NC}"
# ویرایش فایل config و اضافه‌کردن DNS
sudo sed -i "s/^#DNS=.*/DNS=$DNS1 $DNS2/" /etc/systemd/resolved.conf
grep -q "^DNS=" /etc/systemd/resolved.conf || echo "DNS=$DNS1 $DNS2" | sudo tee -a /etc/systemd/resolved.conf > /dev/null

echo -e "${BLUE}🔧 فعال‌سازی systemd-resolved...${NC}"
sudo systemctl enable systemd-resolved
sudo systemctl restart systemd-resolved

echo -e "${BLUE}🔗 لینک کردن resolv.conf به systemd-resolved...${NC}"
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

echo -e "${BLUE}🔧 بررسی hostname و اصلاح /etc/hosts (برای رفع خطای sudo)...${NC}"
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo -e "${YELLOW}⚠️  اصلاح /etc/hosts برای hostname: $HOSTNAME${NC}"
    sudo sed -i "/127.0.1.1/d" /etc/hosts
    echo "127.0.1.1   $HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
fi

echo -e "${GREEN}✅ تنظیمات DNS انجام شد و مشکل DNS Leak برطرف شد.${NC}"
echo -e "${BLUE}🔍 لطفاً نتیجه را در این سایت بررسی کنید:${NC}"
echo -e "${YELLOW}➡️  https://dnsleaktest.com${NC}"
