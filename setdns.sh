#!/bin/bash

# رنگ‌ها
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo -e "${BLUE}🌐 اجرای نسخه نهایی و کنترل‌شده ضد DNS Leak...${NC}"
sleep 1

# نصب ابزارهای ضروری
REQUIRED_PKGS=(curl jq dnsutils resolvconf)
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -l | grep -qw "$pkg"; then
        echo -e "${YELLOW}🔧 نصب ${pkg}...${NC}"
        sudo apt install -y "$pkg"
    fi
done

# مرحله 1: تشخیص موقعیت سرور
INFO=$(curl -s https://ipinfo.io)
IP=$(echo "$INFO" | jq -r .ip)
COUNTRY=$(echo "$INFO" | jq -r .country)
CITY=$(echo "$INFO" | jq -r .city)

echo -e "${BLUE}🛰️ موقعیت سرور: ${GREEN}$COUNTRY - $CITY${NC}"
echo -e "${BLUE}🌐 IP سرور: ${GREEN}$IP${NC}"

# مرحله 2: واکشی لیست DNS عمومی با فیلتر دقیق IP معتبر
echo -e "${BLUE}🌐 واکشی و فیلتر دقیق IPهای معتبر از dnscheck.tools...${NC}"
DNS_RAW=$(curl -s https://dnscheck.tools/ | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' |
  awk -F. '($1<=255 && $2<=255 && $3<=255 && $4<=255)' | sort -u)

# مرحله 3: تست DNSها بر اساس موقعیت و پاسخ‌گویی
VALID_DNS_LIST=()
echo -e "${YELLOW}🔍 بررسی DNSهای پاسخگو در کشور $COUNTRY...${NC}"
for dns in $DNS_RAW; do
    LOC=$(curl -s https://ipinfo.io/$dns | jq -r '.country + " " + .city')
    if [[ "$LOC" == "$COUNTRY "* ]]; then
        if dig +time=1 +tries=1 @$dns example.com | grep -q "ANSWER:"; then
            echo -e "${GREEN}✅ $dns فعال و در $LOC${NC}"
            VALID_DNS_LIST+=("$dns")
        else
            echo -e "${RED}❌ $dns در $LOC پاسخگو نیست${NC}"
        fi
    else
        echo -e "${RED}⚠️ $dns در کشور دیگری قرار دارد ($LOC)${NC}"
    fi
done

# مرحله 4: fallback در صورت نبود DNS مناسب
if [ ${#VALID_DNS_LIST[@]} -eq 0 ]; then
    echo -e "${RED}🚨 هیچ DNS معتبر در کشور $COUNTRY یافت نشد. استفاده از Cloudflare به عنوان fallback.${NC}"
    VALID_DNS_LIST=("1.1.1.1" "1.0.0.1")
fi

# مرحله 5: اعمال به systemd-resolved
DNS_LINE=$(IFS=" "; echo "${VALID_DNS_LIST[*]}")
echo -e "${BLUE}⚙️ اعمال DNS به systemd-resolved: $DNS_LINE${NC}"
sudo sed -i '/^DNS=/d;/^FallbackDNS=/d' /etc/systemd/resolved.conf
echo -e "[Resolve]\nDNS=$DNS_LINE\nFallbackDNS=" | sudo tee /etc/systemd/resolved.conf > /dev/null
sudo systemctl restart systemd-resolved
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

# اصلاح hosts
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo -e "${YELLOW}🩺 اصلاح فایل hosts برای hostname: $HOSTNAME${NC}"
    sudo sed -i "/127.0.1.1/d" /etc/hosts
    echo "127.0.1.1   $HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
fi

# مرحله نهایی: بررسی DNS فعال و احتمال نشتی
echo -e "\n${BLUE}🧪 بررسی نهایی با dig...${NC}"
ACTIVE_DNS=$(dig example.com | grep "SERVER" | awk '{print $3}')
echo -e "${YELLOW}🧭 DNS فعال: $ACTIVE_DNS${NC}"

if [[ "$ACTIVE_DNS" =~ ^(1\.1\.1\.1|1\.0\.0\.1|8\.8\.8\.8|9\.9\.9\.9)$ ]]; then
    echo -e "${RED}❌ احتمال DNS Leak وجود دارد! DNS منطقه‌ای فعال نیست.${NC}"
else
    echo -e "${GREEN}✅ بدون نشتی DNS! از DNS بومی استفاده شده است.${NC}"
fi

echo -e "${YELLOW}🔗 برای بررسی دقیق‌تر: https://dnsleaktest.com${NC}"
