#!/bin/bash

# رنگ‌ها
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo -e "${BLUE}🌐 اجرای اسکریپت نهایی ضد DNS Leak برای Ubuntu 22.04...${NC}"
sleep 1
echo -e "${BLUE} BigPyth0n...${NC}"
sleep 2
# نصب ابزارهای ضروری
REQUIRED_PKGS=(curl jq resolvconf tcpdump dnsutils)
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -l | grep -qw "$pkg"; then
        echo -e "${YELLOW}🔧 در حال نصب ${pkg}...${NC}"
        sudo apt install -y "$pkg"
    fi
done

# دریافت اطلاعات سرور
INFO=$(curl -s https://ipinfo.io)
IP=$(echo "$INFO" | jq -r .ip)
COUNTRY=$(echo "$INFO" | jq -r .country)
ORG=$(echo "$INFO" | jq -r .org)
CITY=$(echo "$INFO" | jq -r .city)

echo -e "${BLUE}🛰️ موقعیت سرور: ${GREEN}$COUNTRY ($CITY) | $ORG${NC}"
echo -e "${BLUE}🌐 IP سرور: ${GREEN}$IP${NC}"

# تعیین DNS بر اساس کشور
case "$COUNTRY" in
  TR)
    DNS1="193.192.98.66"
    DNS2="212.156.4.20"
    LABEL="🇹🇷 DNS ترکیه (Turk Telekom)"
    ;;
  DE)
    DNS1="194.150.168.168"
    DNS2="194.150.168.169"
    LABEL="🇩🇪 DNS آلمان (CCC)"
    ;;
  NL)
    DNS1="80.65.64.13"
    DNS2="80.65.64.14"
    LABEL="🇳🇱 DNS هلند (Bit)"
    ;;
  US)
    DNS1="9.9.9.9"
    DNS2="149.112.112.112"
    LABEL="🇺🇸 DNS آمریکا (Quad9)"
    ;;
  *)
    DNS1="1.1.1.1"
    DNS2="1.0.0.1"
    LABEL="🌐 DNS عمومی (Cloudflare)"
    ;;
esac

echo -e "${YELLOW}✅ تنظیم DNS برای $COUNTRY → $LABEL${NC}"

# تنظیم systemd-resolved
echo -e "${BLUE}🔧 تنظیم systemd-resolved...${NC}"
sudo sed -i '/^DNS=/d;/^FallbackDNS=/d' /etc/systemd/resolved.conf
echo -e "[Resolve]\nDNS=$DNS1 $DNS2\nFallbackDNS=" | sudo tee /etc/systemd/resolved.conf > /dev/null

# راه‌اندازی مجدد سرویس
sudo systemctl restart systemd-resolved

# اطمینان از اتصال صحیح resolv.conf
echo -e "${BLUE}🔗 تنظیم symlink صحیح برای /etc/resolv.conf...${NC}"
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

# اصلاح /etc/hosts در صورت نیاز
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo -e "${YELLOW}🩺 اصلاح فایل hosts برای hostname: $HOSTNAME${NC}"
    sudo sed -i "/127.0.1.1/d" /etc/hosts
    echo "127.0.1.1   $HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
fi

# تست نهایی با dig
echo -e "\n${BLUE}🧪 اجرای تست dig برای بررسی DNS فعال...${NC}"
DNS_USED=$(dig +short example.com | head -n1)
SERVER_USED=$(dig example.com | grep "SERVER" | awk '{print $3}')

echo -e "${YELLOW}🌍 IP برگشتی: $DNS_USED${NC}"
echo -e "${YELLOW}🧭 سرور DNS فعال: $SERVER_USED${NC}"

# بررسی نشتی واقعی با tcpdump (برای 3 ثانیه)
echo -e "\n${BLUE}🔍 بررسی زنده نشتی DNS با tcpdump (3 ثانیه)...${NC}"
sudo timeout 3 tcpdump -i any port 53 -nn

echo -e "\n${GREEN}✅ تنظیمات اعمال شد. اگر در خروجی tcpdump فقط DNS کشور شما ظاهر شد، نشتی وجود ندارد.${NC}"
echo -e "${YELLOW}💡 همچنین برای اطمینان بیشتر می‌توانید به https://dnsleaktest.com مراجعه نمایید.${NC}"
