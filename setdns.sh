#!/bin/bash

# رنگ‌ها
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo -e "${BLUE}🌐 برنامه‌نویس: BigPyth0n${NC}"
echo -e "${BLUE}🧠 اجرای نسخه نهایی و کنترل‌شده ضد DNS Leak...${NC}"
sleep 1

# نمایش وضعیت hostname قبل از هر اصلاح
echo -e "\n${YELLOW}📌 وضعیت اولیه hostname:${NC}"
hostnamectl status

# استخراج hostname فعلی
CURRENT_HOSTNAME=$(hostname)
STATIC_HOSTNAME=$(hostnamectl status | grep "Static hostname" | awk '{print $3}')

# اگر Static hostname ست نشده بود، تنظیمش کن
if [[ "$STATIC_HOSTNAME" == "n/a" || -z "$STATIC_HOSTNAME" ]]; then
    echo -e "${YELLOW}🧩 تنظیم Static hostname به: $CURRENT_HOSTNAME${NC}"
    echo "$CURRENT_HOSTNAME" | sudo tee /etc/hostname > /dev/null
    sudo hostnamectl set-hostname "$CURRENT_HOSTNAME"
    sleep 1
fi

# اصلاح فایل /etc/hosts
if ! grep -q "$CURRENT_HOSTNAME" /etc/hosts; then
    echo -e "${YELLOW}🩺 اصلاح /etc/hosts برای hostname: $CURRENT_HOSTNAME${NC}"
    sudo sed -i '/127.0.1.1/d' /etc/hosts
    echo "127.0.1.1 $CURRENT_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
fi

# تأیید نهایی اصلاح hostname
echo -e "\n${GREEN}✅ بررسی مجدد وضعیت hostname بعد از اصلاح:${NC}"
hostnamectl status
echo -e "${YELLOW}📄 محتوای فایل /etc/hostname:${NC}"
cat /etc/hostname

# ادامه تنظیمات DNS
echo -e "${YELLOW}\n🔧 تنظیم DNS اولیه برای نصب پکیج‌ها...${NC}"
echo -e "[Resolve]\nDNS=1.1.1.1 1.0.0.1\nFallbackDNS=" | sudo tee /etc/systemd/resolved.conf > /dev/null
sudo systemctl restart systemd-resolved
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

# نصب ابزارهای ضروری
REQUIRED_PKGS=(curl jq dnsutils resolvconf net-tools lsb-release wget)
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -l | grep -qw "$pkg"; then
        echo -e "${YELLOW}🔧 نصب ${pkg}...${NC}"
        sudo apt-get update -qq
        sudo apt-get install -y -qq "$pkg" >/dev/null
    fi
done

# دریافت اطلاعات سرور
IP=$(curl -s https://ipinfo.io/ip || echo "Unknown")
COUNTRY=$(curl -s https://ipinfo.io/country || echo "Unknown")
CITY=$(curl -s https://ipinfo.io/city || echo "Unknown")
TIMEZONE=$(curl -s https://ipinfo.io/timezone || echo "UTC")

echo -e "${BLUE}🛰️ موقعیت سرور: ${GREEN}${COUNTRY} - ${CITY}${NC}"
echo -e "${BLUE}🌐 IP سرور: ${GREEN}${IP}${NC}"
echo -e "${BLUE}⏰ تایم‌زون مناسب: ${GREEN}${TIMEZONE}${NC}"
sudo timedatectl set-timezone "$TIMEZONE" 2>/dev/null

# واکشی DNS بومی از Github
echo -e "${BLUE}🌐 واکشی لیست DNSها از dnscheck.tools...${NC}"
DNS_LIST=$(curl -s https://raw.githubusercontent.com/oneofcode/public-dns/main/dns_${COUNTRY,,}.json | jq -r '.[].ip' | head -n 5)

echo -e "${YELLOW}🔍 بررسی DNSهای پاسخگو در کشور $COUNTRY...${NC}"
VALID_DNS=()
for dns in $DNS_LIST; do
    if timeout 1 dig +short @"$dns" example.com > /dev/null 2>&1; then
        LOC=$(curl -s https://ipinfo.io/$dns | jq -r '.country + " " + .city')
        echo -e "${GREEN}✅ $dns فعال در $LOC${NC}"
        VALID_DNS+=("$dns")
    else
        echo -e "${RED}⚠️ $dns پاسخگو نیست${NC}"
    fi
done

# fallback در صورت نبود DNS سالم
if [ ${#VALID_DNS[@]} -eq 0 ]; then
    echo -e "${RED}🚨 هیچ DNS بومی یافت نشد! استفاده از Cloudflare...${NC}"
    VALID_DNS=("1.1.1.1" "1.0.0.1")
fi

# اعمال به systemd-resolved
DNS_LINE=$(IFS=" "; echo "${VALID_DNS[*]}")
echo -e "${BLUE}⚙️ اعمال DNS به systemd-resolved: ${DNS_LINE}${NC}"
sudo sed -i '/^DNS=/d;/^FallbackDNS=/d' /etc/systemd/resolved.conf
echo -e "[Resolve]\nDNS=${DNS_LINE}\nFallbackDNS=" | sudo tee /etc/systemd/resolved.conf > /dev/null
sudo systemctl restart systemd-resolved
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

# نصب cloudflared
echo -e "${BLUE}🚀 نصب cloudflared برای جلوگیری از WebRTC Leak...${NC}"
ARCH=$(dpkg --print-architecture)
URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
wget -q "$URL" -O cloudflared.deb && sudo dpkg -i cloudflared.deb >/dev/null && rm cloudflared.deb

# اجرای DNS Proxy
echo -e "${YELLOW}🛡️ اجرای Cloudflare DNS Proxy در پورت 5053...${NC}"
nohup cloudflared proxy-dns --port 5053 --upstream https://1.1.1.1/dns-query --upstream https://1.0.0.1/dns-query > /dev/null 2>&1 &

# بررسی نهایی
echo -e "\n${BLUE}🧪 بررسی نهایی با dig...${NC}"
ACTIVE_DNS=$(dig example.com | grep SERVER | awk '{print $3}')
echo -e "${YELLOW}🧭 DNS فعال: ${ACTIVE_DNS}${NC}"

if [[ "$ACTIVE_DNS" =~ ^(1\.1\.1\.1|1\.0\.0\.1|8\.8\.8\.8|9\.9\.9\.9)$ ]]; then
    echo -e "${RED}❌ احتمال DNS Leak! DNS عمومی استفاده شده است.${NC}"
else
    echo -e "${GREEN}✅ بدون نشتی DNS! از DNS محلی یا امن استفاده شده است.${NC}"
fi

echo -e "${YELLOW}🔗 بررسی دقیق‌تر: https://dnsleaktest.com | https://browserleaks.com/webrtc${NC}"
