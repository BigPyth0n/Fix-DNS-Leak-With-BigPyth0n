#!/bin/bash

# رنگ‌ها
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOGFILE="/var/log/dns-secure.log"
exec > >(tee -a "$LOGFILE") 2>&1

clear
echo -e "${BLUE}🌐 برنامه‌نویس: BigPyth0n${NC}"
echo -e "${BLUE}🧠 اجرای نسخه نهایی و کنترل‌شده ضد DNS و WebRTC Leak...${NC}"

# نصب ابزارهای مورد نیاز بدون کش
REQUIRED_PKGS=(curl jq dnsutils resolvconf net-tools iptables iptables-persistent)
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -l | grep -qw "$pkg"; then
        echo -e "${YELLOW}🔧 نصب ${pkg} (بدون کش)...${NC}"
        sudo apt clean
        sudo rm -rf /var/lib/apt/lists/*
        sudo apt update -o Acquire::http::No-Cache=true -o Acquire::https::No-Cache=true
        sudo apt install --no-install-recommends -y "$pkg"
    fi
done

# دریافت موقعیت سرور
INFO=$(curl -s https://ipinfo.io)
IP=$(echo "$INFO" | jq -r .ip)
COUNTRY=$(echo "$INFO" | jq -r .country)
CITY=$(echo "$INFO" | jq -r .city)
TIMEZONE=$(echo "$INFO" | jq -r .timezone)

echo -e "${BLUE}🛰️ موقعیت سرور: ${GREEN}$COUNTRY - $CITY${NC}"
echo -e "${BLUE}🌐 IP سرور: ${GREEN}$IP${NC}"
echo -e "${BLUE}⏰ تایم‌زون مناسب: ${GREEN}$TIMEZONE${NC}"

# تنظیم timezone
if [ -n "$TIMEZONE" ]; then
    sudo timedatectl set-timezone "$TIMEZONE"
fi

# واکشی لیست DNS
echo -e "${BLUE}🌐 واکشی لیست DNSها از dnscheck.tools...${NC}"
DNS_RAW=$(curl -s https://dnscheck.tools/ | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' |
  awk -F. '($1<=255 && $2<=255 && $3<=255 && $4<=255)' | sort -u)

VALID_DNS_LIST=()
echo -e "${YELLOW}🔍 بررسی DNSهای پاسخگو در کشور $COUNTRY...${NC}"
for dns in $DNS_RAW; do
    LOC=$(curl -s https://ipinfo.io/$dns | jq -r '.country + " " + .city')
    if [[ "$LOC" == "$COUNTRY "* ]]; then
        if dig +time=1 +tries=1 @"$dns" example.com | grep -q "ANSWER:"; then
            echo -e "${GREEN}✅ $dns فعال در $LOC${NC}"
            VALID_DNS_LIST+=("$dns")
        else
            echo -e "${RED}❌ $dns در $LOC پاسخگو نیست${NC}"
        fi
    else
        echo -e "${RED}⚠️ $dns در کشور دیگری است: ($LOC)${NC}"
    fi
done

# fallback
if [ ${#VALID_DNS_LIST[@]} -eq 0 ]; then
    echo -e "${RED}🚨 هیچ DNS بومی یافت نشد! استفاده از Cloudflare...${NC}"
    VALID_DNS_LIST=("1.1.1.1" "1.0.0.1")
fi

# تنظیم systemd-resolved
DNS_LINE=$(IFS=" "; echo "${VALID_DNS_LIST[*]}")
echo -e "${BLUE}⚙️ اعمال DNS به systemd-resolved: $DNS_LINE${NC}"
sudo sed -i '/^DNS=/d;/^FallbackDNS=/d' /etc/systemd/resolved.conf
echo -e "[Resolve]\nDNS=$DNS_LINE\nFallbackDNS=" | sudo tee /etc/systemd/resolved.conf > /dev/null
sudo systemctl restart systemd-resolved
sudo resolvectl flush-caches
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

# اصلاح hosts
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo -e "${YELLOW}🩺 اصلاح /etc/hosts برای $HOSTNAME${NC}"
    sudo sed -i "/127.0.1.1/d" /etc/hosts
    echo "127.0.1.1   $HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
fi

# بلاک WebRTC Ports
echo -e "${BLUE}🚫 بلاک پورت‌های WebRTC و STUN/ICE با iptables...${NC}"
sudo iptables -A OUTPUT -p udp --dport 3478 -j DROP
sudo iptables -A OUTPUT -p udp --dport 5349 -j DROP
sudo iptables -A OUTPUT -p udp --dport 10000:65535 -j DROP
sudo netfilter-persistent save

# بررسی نهایی
echo -e "${BLUE}🧪 بررسی نهایی با dig...${NC}"
ACTIVE_DNS=$(dig example.com | grep "SERVER" | awk '{print $3}')
echo -e "${YELLOW}🧭 DNS فعال: $ACTIVE_DNS${NC}"

if [[ "$ACTIVE_DNS" =~ ^(1\.1\.1\.1|1\.0\.0\.1|8\.8\.8\.8|9\.9\.9\.9)$ ]]; then
    echo -e "${RED}❌ احتمال DNS Leak! DNS بومی استفاده نشده.${NC}"
else
    echo -e "${GREEN}✅ بدون نشتی DNS! از DNS محلی استفاده شده است.${NC}"
fi

echo -e "${YELLOW}🔗 بررسی دقیق‌تر: https://dnsleaktest.com | https://browserleaks.com/webrtc${NC}"
