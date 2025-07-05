#!/bin/bash

# رنگ‌ها
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo -e "${BLUE}🌐 اجرای اسکریپت نهایی هوشمند جلوگیری از DNS Leak...${NC}"
sleep 1

# نصب ابزارهای ضروری
REQUIRED_PKGS=(curl jq dig dnsutils resolvconf)
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

# مرحله 2: واکشی DNSهای محلی از dnscheck.tools
echo -e "${BLUE}🌐 در حال واکشی DNSهای منطقه‌ای از dnscheck.tools...${NC}"
DNS_RAW=$(curl -s https://dnscheck.tools/ | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)

# مرحله 3: فیلتر DNSهایی که در همان کشور هستند (فقط استانبول/TR در این نسخه)
VALID_DNS_LIST=()
echo -e "${YELLOW}🔎 بررسی فعال بودن DNSها...${NC}"
for dns in $DNS_RAW; do
    LOC=$(curl -s https://ipinfo.io/$dns | jq -r '.country + " " + .city')
    if [[ "$LOC" == "$COUNTRY "* ]]; then
        # تست پاسخگویی DNS
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

# مرحله 4: بررسی اینکه حداقل یک DNS معتبر یافت شده یا نه
if [ ${#VALID_DNS_LIST[@]} -eq 0 ]; then
    echo -e "${RED}🚨 هیچ DNS معتبر و فعال در کشور $COUNTRY یافت نشد. استفاده از Cloudflare به عنوان پیش‌فرض.${NC}"
    VALID_DNS_LIST=("1.1.1.1" "1.0.0.1")
fi

# مرحله 5: ست کردن DNSها در systemd-resolved
DNS_LINE=$(IFS=" "; echo "${VALID_DNS_LIST[*]}")
echo -e "${BLUE}⚙️ تنظیم systemd-resolved با DNSهای: $DNS_LINE${NC}"
sudo sed -i '/^DNS=/d;/^FallbackDNS=/d' /etc/systemd/resolved.conf
echo -e "[Resolve]\nDNS=$DNS_LINE\nFallbackDNS=" | sudo tee /etc/systemd/resolved.conf > /dev/null
sudo systemctl restart systemd-resolved

# اطمینان از اتصال صحیح resolv.conf
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

# اصلاح /etc/hosts در صورت نیاز
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo -e "${YELLOW}🩺 اصلاح فایل hosts برای hostname: $HOSTNAME${NC}"
    sudo sed -i "/127.0.1.1/d" /etc/hosts
    echo "127.0.1.1   $HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
fi

# مرحله نهایی: تایید DNS فعال
echo -e "\n${BLUE}🧪 بررسی نهایی با dig...${NC}"
dig example.com | grep "SERVER"

echo -e "\n${GREEN}✅ تنظیمات DNS هوشمند با موفقیت انجام شد.${NC}"
echo -e "${YELLOW}💡 برای بررسی کامل‌تر وارد سایت زیر شوید:${NC}"
echo -e "${YELLOW}➡️  https://dnsleaktest.com${NC}"
