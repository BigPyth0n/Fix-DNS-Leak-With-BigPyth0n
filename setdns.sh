#!/bin/bash

# رنگ‌ها
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo -e "${BLUE}🌐 اجرای اسکریپت حرفه‌ای ضد DNS Leak...${NC}"
sleep 1

# بررسی و نصب ابزارهای لازم
REQUIRED_PKGS=(curl jq resolvconf)
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -l | grep -qw "$pkg"; then
        echo -e "${YELLOW}🔧 نصب ${pkg}...${NC}"
        sudo apt install -y "$pkg"
    fi
done

# دریافت اطلاعات IP
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

# تنظیم resolvconf
echo -e "${BLUE}🔧 تنظیم resolvconf...${NC}"
echo -e "nameserver $DNS1\nnameserver $DNS2" | sudo tee /etc/resolvconf/resolv.conf.d/base > /dev/null
sudo resolvconf -u

# تنظیم systemd-resolved
echo -e "${BLUE}🔧 تنظیم systemd-resolved...${NC}"
sudo sed -i "s/^#DNS=.*/DNS=$DNS1 $DNS2/" /etc/systemd/resolved.conf
grep -q "^DNS=" /etc/systemd/resolved.conf || echo "DNS=$DNS1 $DNS2" | sudo tee -a /etc/systemd/resolved.conf > /dev/null
sudo systemctl enable systemd-resolved
sudo systemctl restart systemd-resolved
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

# اصلاح hosts
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo -e "${YELLOW}🩺 اصلاح فایل hosts برای hostname: $HOSTNAME${NC}"
    sudo sed -i "/127.0.1.1/d" /etc/hosts
    echo "127.0.1.1   $HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
fi

# نمایش پایان و تست
echo -e "\n${GREEN}✅ تنظیمات DNS با موفقیت انجام شد.${NC}"
echo -e "${BLUE}🔍 اجرای Extended DNS Leak Test (از طریق dnsleaktest.com)...${NC}"
sleep 2

TEST_URL="https://www.dnsleaktest.com/"
echo -e "${YELLOW}📥 دریافت اطلاعات تست...${NC}"
RESULT=$(curl -s "$TEST_URL" | grep -A20 "Your IP" | sed 's/^/    /')
echo -e "${GREEN}🧪 نتیجه تست:${NC}\n$RESULT"

echo -e "\n${GREEN}🏁 پایان اسکریپت. اگر نتایج صحیح نبود، دستی بررسی کنید:${NC}"
echo -e "${YELLOW}➡️  https://dnsleaktest.com${NC}"
