#!/bin/bash

# رنگ‌ها
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear

echo -e "${BLUE}🌐 برنامه‌نویس: Big${NC}"
echo -e "${BLUE}🧠 اجرای نسخه نهایی و کنترل‌شده ضد DNS Leak...${NC}"

# نصب ابزارهای مورد نیاز
REQUIRED_PKGS=(curl jq dnsutils resolvconf dbus tzdata net-tools lsb-release)
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -l | grep -qw "$pkg"; then
        echo -e "${YELLOW}🔧 نصب $pkg...${NC}"
        apt-get update -qq
        apt-get install -y "$pkg"
    fi
done

# 🔹 موقعیت و timezone
INFO=$(curl -s https://ipinfo.io)
IP=$(echo "$INFO" | jq -r .ip)
COUNTRY=$(echo "$INFO" | jq -r .country)
CITY=$(echo "$INFO" | jq -r .city)
TZ=$(curl -s https://ipapi.co/timezone)

echo -e "${BLUE}🛰️ موقعیت سرور: ${GREEN}$COUNTRY - $CITY${NC}"
echo -e "${BLUE}🌐 IP سرور: ${GREEN}$IP${NC}"
echo -e "${BLUE}⏰ تایم‌زون مناسب: ${GREEN}$TZ${NC}"
timedatectl set-timezone "$TZ"

# 🔹 دریافت DNS معتبر
echo -e "${BLUE}🌐 واکشی لیست DNSها از dnscheck.tools...${NC}"
DNS_RAW=$(curl -s https://dnscheck.tools/ | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)

VALID_DNS_LIST=()
for dns in $DNS_RAW; do
    LOC=$(curl -s https://ipinfo.io/$dns | jq -r '.country + " " + .city')
    if [[ "$LOC" == "$COUNTRY "* ]]; then
        if dig +time=1 +tries=1 @"$dns" example.com | grep -q "ANSWER:"; then
            echo -e "${GREEN}✅ $dns فعال و در $LOC${NC}"
            VALID_DNS_LIST+=("$dns")
        else
            echo -e "${RED}❌ $dns در $LOC پاسخگو نیست${NC}"
        fi
    else
        echo -e "${RED}⚠️ $dns در کشور دیگری قرار دارد ($LOC)${NC}"
    fi
done

# 🔹 fallback
if [ ${#VALID_DNS_LIST[@]} -eq 0 ]; then
    echo -e "${RED}🚨 هیچ DNS بومی یافت نشد! استفاده از Cloudflare...${NC}"
    VALID_DNS_LIST=("1.1.1.1" "1.0.0.1")
fi

# 🔹 اعمال DNS
DNS_LINE=$(IFS=" "; echo "${VALID_DNS_LIST[*]}")
echo -e "${BLUE}⚙️ اعمال DNS به systemd-resolved: ${GREEN}$DNS_LINE${NC}"
sudo sed -i '/^DNS=/d;/^FallbackDNS=/d' /etc/systemd/resolved.conf
echo -e "[Resolve]\nDNS=$DNS_LINE\nFallbackDNS=" > /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
resolvectl flush-caches

# 🔹 فایل hosts
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo -e "${YELLOW}🩺 اصلاح فایل hosts برای hostname: $HOSTNAME${NC}"
    sed -i "/127.0.1.1/d" /etc/hosts
    echo "127.0.1.1   $HOSTNAME" >> /etc/hosts
fi

# 🔹 بررسی نهایی DNS
echo -e "\n${BLUE}🧪 بررسی نهایی با dig...${NC}"
ACTIVE_DNS=$(dig example.com | grep "SERVER" | awk '{print $3}')
echo -e "${YELLOW}🧭 DNS فعال: $ACTIVE_DNS${NC}"

# 🔹 تشخیص نشتی WebRTC از طریق IP خارجی
if curl -s https://ipinfo.io/46.36.100.112 | grep -q "Iran"; then
    echo -e "${RED}🚨 WebRTC Leak از آدرس مشکوک ایران: 46.36.100.112${NC}"
    echo -e "${YELLOW}💡 پیشنهاد: بلاک WebRTC از سمت مرورگر یا استفاده از iptables${NC}"

    # تنظیمات پیشنهادی سیستم برای بلاک WebRTC (سطح پایین)
    iptables -A OUTPUT -p udp --dport 3478 -j DROP
    iptables -A OUTPUT -p udp --dport 19302 -j DROP
    echo -e "${GREEN}🛡️ ترافیک WebRTC به پورت‌های STUN/UDP مسدود شد.${NC}"
fi

echo -e "${GREEN}✅ پیکربندی با موفقیت انجام شد.${NC}"
echo -e "${YELLOW}🔗 بررسی دقیق‌تر: https://dnsleaktest.com | https://browserleaks.com/webrtc${NC}"
