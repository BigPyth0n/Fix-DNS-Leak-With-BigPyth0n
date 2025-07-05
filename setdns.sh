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
sleep 1

# نمایش وضعیت اولیه hostname
echo -e "\n${YELLOW}📌 وضعیت اولیه hostname:${NC}"
hostnamectl status

# اصلاح hostname اگر نیاز بود
CURRENT_HOSTNAME=$(hostname)
STATIC_HOSTNAME=$(hostnamectl status | grep "Static hostname" | awk '{print $3}')
if [[ "$STATIC_HOSTNAME" == "n/a" || -z "$STATIC_HOSTNAME" ]]; then
    echo -e "${YELLOW}🧩 تنظیم Static hostname به: $CURRENT_HOSTNAME${NC}"
    echo "$CURRENT_HOSTNAME" | sudo tee /etc/hostname > /dev/null
    sudo hostnamectl set-hostname "$CURRENT_HOSTNAME"
    sleep 1
fi

# اصلاح /etc/hosts
if ! grep -q "$CURRENT_HOSTNAME" /etc/hosts; then
    echo -e "${YELLOW}🩺 اصلاح /etc/hosts برای hostname: $CURRENT_HOSTNAME${NC}"
    sudo sed -i '/127.0.1.1/d' /etc/hosts
    echo "127.0.1.1 $CURRENT_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
fi

# تأیید hostname
echo -e "\n${GREEN}✅ بررسی مجدد وضعیت hostname:${NC}"
hostnamectl status
echo -e "${YELLOW}📄 محتوای فایل /etc/hostname:${NC}"
cat /etc/hostname

# دریافت کشور
COUNTRY=$(curl -s https://ipinfo.io/country)
echo -e "\n${YELLOW}🌍 کشور شناسایی‌شده: $COUNTRY${NC}"

# واکشی و تست DNS بومی
echo -e "${YELLOW}🔍 بررسی DNSهای سالم برای کشور $COUNTRY...${NC}"
DNS_CANDIDATES=$(curl -s https://public-dns.info/nameservers.csv | grep ",$COUNTRY" | cut -d, -f1 | grep -v ":" | grep -v "^ip_address" | head -n 5)

VALID_DNS=()
for dns in $DNS_CANDIDATES; do
  echo -ne "⏳ تست $dns ... "
  if timeout 1 dig +short @"$dns" example.com > /dev/null 2>&1; then
    echo -e "${GREEN}✅ OK${NC}"
    VALID_DNS+=("$dns")
  else
    echo -e "${RED}❌ Failed${NC}"
  fi
done

# اگر هیچ DNS سالم نبود، fallback
if [ ${#VALID_DNS[@]} -eq 0 ]; then
    echo -e "${RED}🚨 هیچ DNS بومی پاسخگو نیست! استفاده از Cloudflare...${NC}"
    VALID_DNS=("1.1.1.1" "1.0.0.1")
fi

# اعمال DNS
DNS_LINE=$(IFS=" "; echo "${VALID_DNS[*]}")
echo -e "${BLUE}⚙️ اعمال DNS: ${DNS_LINE}${NC}"
echo -e "[Resolve]\nDNS=${DNS_LINE}\nFallbackDNS=" | sudo tee /etc/systemd/resolved.conf > /dev/null
sudo systemctl restart systemd-resolved
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

# تست نهایی
echo -e "\n${BLUE}🧪 بررسی نهایی با dig...${NC}"
ACTIVE_DNS=$(dig example.com | grep SERVER | awk '{print $3}')
echo -e "${YELLOW}🧭 DNS فعال: ${ACTIVE_DNS}${NC}"

if [[ "$ACTIVE_DNS" =~ ^(1\.1\.1\.1|1\.0\.0\.1|8\.8\.8\.8|9\.9\.9\.9)$ ]]; then
    echo -e "${RED}⚠️ هشدار: DNS عمومی در حال استفاده است!${NC}"
else
    echo -e "${GREEN}✅ بدون نشتی DNS! از DNS محلی یا سالم استفاده شده است.${NC}"
fi

echo -e "${YELLOW}🔗 بررسی دقیق‌تر: https://dnsleaktest.com | https://browserleaks.com/webrtc${NC}"
