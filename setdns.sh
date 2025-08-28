#!/bin/bash

#================================================================================
# اسکریپت بهینه‌سازی و ضد نشت DNS برای سرورهای لینوکس (مبتنی بر دبیان/اوبونتو)
# برنامه‌نویس اصلی: Big
# بازبینی و بهینه‌سازی: Alisa
# نسخه: 3.0 (استفاده از لینک دانلود مستقیم و پایدار)
#================================================================================

# --- رنگ‌ها برای خروجی بهتر ---
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- تنظیمات عمومی ---
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# --- بررسی دسترسی روت ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ لطفاً این اسکریپت را با دسترسی root یا با sudo اجرا کنید.${NC}"
    exit 1
fi

clear
echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}      🚀 اسکریپت حرفه‌ای ضد DNS Leak (نسخه 3.0) 🚀      ${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo -e "برنامه‌نویس اصلی: Big | بازبینی و بهبود: Alisa\n"

# --- بررسی اتصال اولیه به اینترنت ---
echo -e "${YELLOW}🌐 [گام 1/6] در حال بررسی اتصال اینترنت (پینگ به 8.8.8.8)...${NC}"
if ! ping -c 3 -W 2 8.8.8.8 > /dev/null 2>&1; then
    echo -e "${RED}❌ خطای اتصال به اینترنت! لطفاً اتصال شبکه را بررسی کنید.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ اتصال اینترنت اولیه برقرار است.${NC}"

# --- گام 2: به‌روزرسانی کامل سیستم و نصب ابزارهای لازم ---
echo -e "\n${YELLOW}🔄 [گام 2/6] در حال به‌روزرسانی کامل سیستم و نصب پکیج‌های ضروری...${NC}"
apt-get update -qq && apt-get upgrade -y -qq -o Dpkg::Options::=--force-confold

# نصب پکیج‌ها
REQUIRED_PKGS=(curl wget jq dnsutils resolvconf net-tools lsb-release)
MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -l | grep -qw "$pkg"; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "🔧 نصب پکیج‌های: ${MISSING_PKGS[*]}"
    apt-get install -y -qq "${MISSING_PKGS[@]}"
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ خطای نصب پکیج‌های ضروری. لطفاً وضعیت APT را بررسی کنید.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ تمام پکیج‌های ضروری از قبل نصب شده‌اند.${NC}"
fi

# --- گام 3: نصب و پیکربندی cloudflared ---
echo -e "\n${BLUE}🚀 [گام 3/6] نصب و پیکربندی Cloudflare Tunnel (cloudflared)...${NC}"
if ! dpkg -l | grep -q 'cloudflared'; then
    ARCH=$(dpkg --print-architecture)
    # استفاده از لینک دانلود مستقیم و پایدار از گیت‌هاب
    DOWNLOAD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"

    echo -e "${YELLOW}⏳ در حال دانلود cloudflared از ${DOWNLOAD_URL}...${NC}"
    if ! wget -q "$DOWNLOAD_URL" -O cloudflared.deb; then
        echo -e "${RED}❌ خطای دانلود cloudflared. لطفاً اتصال به اینترنت و دسترسی به گیت‌هاب را بررسی کنید.${NC}"
        exit 1
    fi

    echo -e "${YELLOW}🔧 در حال نصب بسته cloudflared...${NC}"
    if ! dpkg -i cloudflared.deb; then
        echo -e "${RED}❌ خطای نصب cloudflared. لطفاً خروجی بالا را بررسی کنید.${NC}"
        rm -f cloudflared.deb
        exit 1
    fi
    rm -f cloudflared.deb
    echo -e "${GREEN}✅ بسته cloudflared با موفقیت نصب شد.${NC}"
else
    echo -e "${GREEN}✅ بسته cloudflared از قبل نصب شده است. از نصب مجدد صرف‌نظر می‌شود.${NC}"
fi

# توقف سرویس در صورت اجرا بودن
systemctl stop cloudflared >/dev/null 2>&1
pkill -f cloudflared >/dev/null 2>&1

# یافتن مسیر اجرایی cloudflared
CLOUDFLARED_BIN=$(which cloudflared)
if [ -z "$CLOUDFLARED_BIN" ]; then
    echo -e "${RED}❌ فایل اجرایی cloudflared یافت نشد! نصب ناموفق بود.${NC}"
    exit 1
fi
echo -e "${GREEN}ℹ️ فایل اجرایی cloudflared در: ${CLOUDFLARED_BIN} یافت شد.${NC}"

# ساخت فایل کانفیگ برای cloudflared
mkdir -p /etc/cloudflared/
cat << EOF > /etc/cloudflared/config.yml
proxy-dns: true
port: 53
address: 127.0.0.1
upstream:
  - https://1.1.1.1/dns-query
  - https://1.0.0.1/dns-query
EOF

# ساخت فایل سرویس systemd
cat << EOF > /etc/systemd/system/cloudflared.service
[Unit]
Description=Cloudflared DNS over HTTPS proxy
After=network.target

[Service]
ExecStart=${CLOUDFLARED_BIN} --config /etc/cloudflared/config.yml
Restart=on-failure
RestartSec=10s
User=nobody
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# فعال‌سازی و راه‌اندازی سرویس
systemctl daemon-reload
systemctl enable --now cloudflared
sleep 3

# بررسی فعال بودن cloudflared
echo -e "${YELLOW}⏳ در حال بررسی فعال بودن Cloudflared روی پورت 53...${NC}"
CHECK_COUNT=0
MAX_CHECKS=15
while ! ss -tulnp | grep -q "127.0.0.1:53"; do
    if [ "$CHECK_COUNT" -ge "$MAX_CHECKS" ]; then
        echo -e "${RED}❌ سرویس cloudflared روی پورت 53 فعال نشد! لطفاً وضعیت را با 'systemctl status cloudflared' بررسی کنید.${NC}"
        exit 1
    fi
    sleep 2
    CHECK_COUNT=$((CHECK_COUNT+1))
done
echo -e "${GREEN}✅ سرویس cloudflared با موفقیت نصب و بر روی 127.0.0.1:53 فعال شد.${NC}"

# --- گام 4: تنظیم سیستم برای استفاده از پراکسی DNS محلی ---
echo -e "\n${BLUE}⚙️ [گام 4/6] تنظیم systemd-resolved برای استفاده از پراکسی محلی...${NC}"
cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak.$(date +%Y%m%d%H%M%S)
cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d%H%M%S)
echo -e "  ${YELLOW}ℹ️ از فایل‌های تنظیمات DNS پشتیبان‌گیری شد.${NC}"
echo -e "[Resolve]\nDNS=127.0.0.1\nDNSStubListener=no" > /etc/systemd/resolved.conf
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl restart systemd-resolved
echo -e "${GREEN}✅ سیستم‌عامل برای ارسال تمام درخواست‌های DNS به 127.0.0.1 پیکربندی شد.${NC}"

# --- گام 5: اصلاح Hostname ---
echo -e "\n${YELLOW}🩺 [گام 5/6] بررسی و اصلاح Hostname و فایل hosts...${NC}"
CURRENT_HOSTNAME=$(hostname)
if ! grep -q "127.0.1.1 $CURRENT_HOSTNAME" /etc/hosts; then
    sed -i '/127.0.1.1/d' /etc/hosts
    echo "127.0.1.1 $CURRENT_HOSTNAME" >> /etc/hosts
    echo -e "  ${GREEN}فایل /etc/hosts اصلاح شد.${NC}"
else
    echo -e "  ${GREEN}فایل /etc/hosts نیازی به اصلاح ندارد.${NC}"
fi

# --- گام 6: بررسی نهایی و تأیید عملکرد ---
echo -e "\n${BLUE}🧪 [گام 6/6] بررسی نهایی و تست DNS...${NC}"
sleep 5

RESPONSE_IP=$(dig +short @127.0.0.1 google.com)
if [ -z "$RESPONSE_IP" ]; then
    echo -e "${RED}❌ هشدار! dig از 127.0.0.1 پاسخی دریافت نکرد.${NC}"
else
    echo -e "  ${YELLOW}🔹 آی‌پی دریافتی برای google.com: ${GREEN}${RESPONSE_IP}${NC}"
fi

ACTIVE_DNS_SERVER=$(dig google.com | grep "SERVER:" | awk '{print $3}' | awk -F'#' '{print $1}')
echo -e "  ${YELLOW}🔹 سرور DNS پاسخ‌دهنده طبق گزارش dig: ${GREEN}${ACTIVE_DNS_SERVER}${NC}"

if [[ "$ACTIVE_DNS_SERVER" == "127.0.0.1" && ! -z "$RESPONSE_IP" ]]; then
    echo -e "\n${GREEN}✅ تبریک! عملیات با موفقیت کامل انجام شد.${NC}"
    echo -e "${GREEN}تمام ترافیک DNS شما اکنون از طریق یک پراکسی امن محلی عبور می‌کند.${NC}"
else
    echo -e "\n${RED}❌ هشدار! پیکربندی به درستی اعمال نشده است.${NC}"
    echo -e "${RED}سرور DNS فعال ${ACTIVE_DNS_SERVER} است، در حالی که انتظار می‌رفت 127.0.0.1 باشد.${NC}"
    echo -e "${RED}لطفاً سرویس‌های systemd-resolved و cloudflared را بررسی کنید.${NC}"
fi

echo -e "\n${YELLOW}🔗 برای اطمینان کامل، نتیجه را در سایت زیر بررسی کنید:${NC}"
echo -e "${BLUE}https://www.dnsleaktest.com/${NC}"
