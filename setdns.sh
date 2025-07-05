#!/bin/bash

# رنگ‌ها
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo -e "${BLUE}🌐 برنامه‌نویس: BigPyth0n${NC}"
echo -e "${BLUE}🧠 نسخه نهایی و حرفه‌ای ضد DNS Leak با منابع معتبر${NC}"

### گام 1: اصلاح hostname و hosts
echo -e "\n${YELLOW}📌 وضعیت اولیه hostname:${NC}"
hostnamectl status

CURRENT_HOSTNAME=$(hostname)
STATIC_HOSTNAME=$(hostnamectl status | grep "Static hostname" | awk '{print $3}')

if [[ "$STATIC_HOSTNAME" == "n/a" || -z "$STATIC_HOSTNAME" ]]; then
    echo -e "${YELLOW}🧩 تنظیم Static hostname به: $CURRENT_HOSTNAME${NC}"
    echo "$CURRENT_HOSTNAME" > /etc/hostname
    hostnamectl set-hostname "$CURRENT_HOSTNAME"
fi

if ! grep -q "$CURRENT_HOSTNAME" /etc/hosts; then
    echo -e "${YELLOW}🩺 اصلاح /etc/hosts برای hostname: $CURRENT_HOSTNAME${NC}"
    sed -i '/127.0.1.1/d' /etc/hosts
    echo "127.0.1.1 $CURRENT_HOSTNAME" >> /etc/hosts
fi

echo -e "\n${GREEN}✅ بررسی مجدد وضعیت hostname:${NC}"
hostnamectl status
echo -e "${YELLOW}📄 محتوای فایل /etc/hostname:${NC}"
cat /etc/hostname

### گام 2: نصب ابزارهای لازم
REQUIRED_PKGS=(curl wget jq dnsutils resolvconf net-tools lsb-release)
MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -l | grep -qw "$pkg"; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}📦 نصب پکیج‌های ضروری: ${MISSING_PKGS[*]}${NC}"
    apt-get update -qq
    apt-get install -y -qq "${MISSING_PKGS[@]}"
fi

### گام 3: دریافت DNSهای سالم بومی
COUNTRY=$(curl -s https://ipinfo.io/country)
echo -e "${BLUE}🌍 کشور شناسایی‌شده: ${GREEN}${COUNTRY}${NC}"
echo -e "${YELLOW}🔍 بررسی DNSهای سالم برای کشور $COUNTRY...${NC}"

DNS_LIST=$(curl -s https://public-dns.info/nameservers.csv | grep ",$COUNTRY" | cut -d, -f1 | grep -v ":" | grep -v "^ip_address" | head -n 5)

VALID_DNS=()
for dns in $DNS_LIST; do
    echo -n "⏳ تست $dns ... "
    if timeout 1 dig +short @"$dns" example.com > /dev/null 2>&1; then
        echo "✅ OK"
        VALID_DNS+=("$dns")
    else
        echo "❌ Failed"
    fi
done

if [ ${#VALID_DNS[@]} -eq 0 ]; then
    echo -e "${RED}🚨 هیچ DNS بومی پاسخگو نیست! استفاده از Cloudflare...${NC}"
    VALID_DNS=("1.1.1.1" "1.0.0.1")
fi

### گام 4: اعمال DNS جدید
DNS_LINE=$(IFS=" "; echo "${VALID_DNS[*]}")
echo -e "${BLUE}⚙️ اعمال DNS: ${DNS_LINE}${NC}"
echo -e "[Resolve]\nDNS=${DNS_LINE}\nFallbackDNS=" > /etc/systemd/resolved.conf
systemctl restart systemd-resolved
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

### گام 5: نصب cloudflared
echo -e "${BLUE}🚀 نصب cloudflared برای جلوگیری از WebRTC Leak...${NC}"
ARCH=$(dpkg --print-architecture)
URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
wget -q "$URL" -O cloudflared.deb && dpkg -i cloudflared.deb >/dev/null && rm cloudflared.deb

### گام 6: اجرای DNS Proxy
echo -e "${YELLOW}🛡️ اجرای Cloudflare DNS Proxy در پورت 5053...${NC}"
nohup cloudflared proxy-dns --port 5053 --upstream https://1.1.1.1/dns-query --upstream https://1.0.0.1/dns-query > /dev/null 2>&1 &

### گام 7: بررسی نهایی
echo -e "\n${BLUE}🧪 بررسی نهایی با dig...${NC}"
ACTIVE_DNS=$(dig example.com | grep SERVER | awk '{print $3}')
echo -e "${YELLOW}🧭 DNS فعال: ${ACTIVE_DNS}${NC}"

if [[ "$ACTIVE_DNS" =~ ^(1\.1\.1\.1|1\.0\.0\.1|8\.8\.8\.8|9\.9\.9\.9)$ ]]; then
    echo -e "${RED}❌ احتمال DNS Leak! DNS عمومی استفاده شده است.${NC}"
else
    echo -e "${GREEN}✅ بدون نشتی DNS! از DNS محلی یا سالم استفاده شده است.${NC}"
fi

echo -e "${YELLOW}🔗 بررسی دقیق‌تر: https://dnsleaktest.com | https://browserleaks.com/webrtc${NC}"
