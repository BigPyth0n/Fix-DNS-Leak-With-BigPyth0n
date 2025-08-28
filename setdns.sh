#!/bin/bash

#================================================================================
# اسکریپت بهینه‌سازی و ضد نشت DNS برای سرورهای لینوکس (مبتنی بر دبیان/اوبونتو)
# برنامه‌نویس اصلی: Big
# بازبینی و بهینه‌سازی: Alisa
# نسخه: 2.1
#
# این اسکریپت سیستم را به‌روز می‌کند، DNSهای سریع و بومی را پیدا کرده و
# با استفاده از cloudflared یک پراکسی امن DNS-over-HTTPS راه‌اندازی می‌کند
# تا تمام ترافیک DNS از یک نقطه واحد و امن عبور کند.
#
# این نسخه برای رفع مشکلات گزارش‌شده در اوبونتو 22.04 و بهینه‌سازی فرایند نصب
# و تشخیص کشور، اصلاح شده است.
#================================================================================

# --- رنگ‌ها برای خروجی بهتر ---
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- بررسی اجرای اسکریپت با دسترسی روت ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ لطفاً این اسکریپت را با دسترسی root یا با sudo اجرا کنید.${NC}"
  exit 1
fi

clear
echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}     🚀 اسکریپت حرفه‌ای ضد DNS Leak (نسخه 2.1) 🚀      ${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo -e "برنامه‌نویس اصلی: Big | بازبینی و بهبود: Alisa\n"


### گام 1: به‌روزرسانی کامل سیستم
echo -e "${YELLOW}🔄 [گام 1/7] در حال به‌روزرسانی کامل سیستم...${NC}"
apt-get update -qq && apt-get upgrade -y -qq -o Dpkg::Options::=--force-confold
echo -e "${GREEN}✅ سیستم با موفقیت به‌روز شد.${NC}"


### گام 2: نصب ابزارهای لازم
echo -e "\n${YELLOW}📦 [گام 2/7] بررسی و نصب پکیج‌های ضروری...${NC}"
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
else
    echo -e "${GREEN}✅ تمام پکیج‌های ضروری از قبل نصب شده‌اند.${NC}"
fi


### گام 3: دریافت و تست DNSهای سالم بومی
COUNTRY=$(curl -s ipapi.co/country)
if [ -z "$COUNTRY" ]; then
    echo -e "${RED}⚠️ [گام 3/7] امکان تشخیص کشور وجود ندارد. از DNS پیش‌فرض استفاده می‌شود.${NC}"
    VALID_DNS=("1.1.1.1" "1.0.0.1")
else
    echo -e "\n${BLUE}🌍 [گام 3/7] کشور شناسایی‌شده: ${GREEN}${COUNTRY}${NC}"
    echo -e "${YELLOW}🔍 در حال جستجو و تست DNSهای عمومی برای کشور ${COUNTRY}...${NC}"

    # دریافت لیست ۵ DNS برتر برای کشور مورد نظر
    DNS_LIST=$(curl -s https://public-dns.info/nameservers.csv | grep ",$COUNTRY" | cut -d, -f1 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 5)

    VALID_DNS=()
    for dns in $DNS_LIST; do
        echo -n "  ⏳ تست $dns ... "
        if timeout 1 dig +short @"$dns" google.com > /dev/null 2>&1; then
            echo -e "${GREEN}✅ پاسخگو${NC}"
            VALID_DNS+=("$dns")
        else
            echo -e "${RED}❌ ناموفق${NC}"
        fi
    done

    if [ ${#VALID_DNS[@]} -eq 0 ]; then
        echo -e "${RED}🚨 هیچ DNS بومی پاسخگو یافت نشد! از DNSهای Cloudflare به عنوان جایگزین استفاده می‌شود.${NC}"
        VALID_DNS=("1.1.1.1" "1.0.0.1")
    fi
fi
echo -e "${GREEN}✅ لیست DNSهای نهایی: ${VALID_DNS[*]}${NC}"


### گام 4: نصب و پیکربندی cloudflared به عنوان سرویس
echo -e "\n${BLUE}🚀 [گام 4/7] نصب و پیکربندی Cloudflare Tunnel (cloudflared)...${NC}"
ARCH=$(dpkg --print-architecture)
URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
wget -q "$URL" -O cloudflared.deb && dpkg -i cloudflared.deb >/dev/null && rm cloudflared.deb

# توقف سرویس در صورت اجرا بودن برای اعمال کانفیگ جدید
systemctl stop cloudflared >/dev/null 2>&1
pkill -f cloudflared >/dev/null 2>&1

# ساخت فایل کانفیگ برای cloudflared
mkdir -p /etc/cloudflared/
UPSTREAM_CONFIG=""
for dns in "${VALID_DNS[@]}"; do
    UPSTREAM_CONFIG+="  - https://${dns}/dns-query\n"
done

cat << EOF > /etc/cloudflared/config.yml
proxy-dns: true
port: 53
address: 127.0.0.1
upstream:
${UPSTREAM_CONFIG}
EOF

# ساخت فایل سرویس systemd به صورت دستی
cat << EOF > /etc/systemd/system/cloudflared.service
[Unit]
Description=Cloudflared DNS over HTTPS proxy
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared --config /etc/cloudflared/config.yml
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

# فعال‌سازی و راه‌اندازی سرویس
systemctl daemon-reload
systemctl enable --now cloudflared
sleep 2 # زمان کوتاه برای اجرای کامل سرویس

if systemctl is-active --quiet cloudflared; then
    echo -e "${GREEN}✅ سرویس cloudflared با موفقیت نصب و با DNSهای بومی پیکربندی شد.${NC}"
else
    echo -e "${RED}❌ خطا در اجرای سرویس cloudflared. لطفاً وضعیت را با 'systemctl status cloudflared' بررسی کنید.${NC}"
    exit 1
fi


### گام 5: تنظیم سیستم برای استفاده از پراکسی DNS محلی
echo -e "\n${BLUE}⚙️ [گام 5/7] تنظیم systemd-resolved برای استفاده از پراکسی محلی...${NC}"
# تمام درخواست‌های DNS سیستم به پراکسی محلی (cloudflared) در 127.0.0.1 ارسال می‌شود
echo -e "[Resolve]\nDNS=127.0.0.1\nDNSStubListener=no" > /etc/systemd/resolved.conf

# اطمینان از اینکه resolv.conf به فایل درست لینک شده
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl restart systemd-resolved
echo -e "${GREEN}✅ سیستم‌عامل برای ارسال تمام درخواست‌های DNS به 127.0.0.1 پیکربندی شد.${NC}"


### گام 6: اصلاح Hostname (برای جلوگیری از خطاهای احتمالی)
echo -e "\n${YELLOW}🩺 [گام 6/7] بررسی و اصلاح Hostname و فایل hosts...${NC}"
CURRENT_HOSTNAME=$(hostname)
if ! grep -q "127.0.1.1 $CURRENT_HOSTNAME" /etc/hosts; then
    sed -i '/127.0.1.1/d' /etc/hosts
    echo "127.0.1.1 $CURRENT_HOSTNAME" >> /etc/hosts
    echo -e "  ${GREEN}فایل /etc/hosts اصلاح شد.${NC}"
else
    echo -e "  ${GREEN}فایل /etc/hosts نیازی به اصلاح ندارد.${NC}"
fi


### گام 7: بررسی نهایی و تأیید عملکرد
echo -e "\n${BLUE}🧪 [گام 7/7] بررسی نهایی و تست DNS...${NC}"
sleep 1 # اطمینان از آماده بودن سرویس‌ها

# با dig از سرور محلی کوئری می‌گیریم
RESPONSE_IP=$(dig +short @127.0.0.1 google.com)
ACTIVE_DNS_SERVER=$(dig google.com | grep "SERVER:" | awk '{print $3}' | awk -F'#' '{print $1}')

echo -e "  ${YELLOW}🔹 سرور DNS پاسخ‌دهنده طبق گزارش dig: ${GREEN}${ACTIVE_DNS_SERVER}${NC}"
echo -e "  ${YELLOW}🔹 آی‌پی دریافتی برای google.com: ${GREEN}${RESPONSE_IP}${NC}"

if [[ "$ACTIVE_DNS_SERVER" == "127.0.0.1" && ! -z "$RESPONSE_IP" ]]; then
    echo -e "\n${GREEN}✅ تبریک! عملیات با موفقیت کامل انجام شد.${NC}"
    echo -e "${GREEN}تمام ترافیک DNS شما اکنون از طریق یک پراکسی امن محلی عبور می‌کند.${NC}"
    echo -e "${GREEN}در تست نشت DNS، فقط باید آی‌پی سرور خود را مشاهده کنید.${NC}"
else
    echo -e "\n${RED}❌ هشدار! پیکربندی به درستی اعمال نشده است.${NC}"
    echo -e "${RED}سرور DNS فعال ${ACTIVE_DNS_SERVER} است، در حالی که انتظار می‌رفت 127.0.0.1 باشد.${NC}"
    echo -e "${RED}لطفاً سرویس‌های systemd-resolved و cloudflared را بررسی کنید.${NC}"
fi

echo -e "\n${YELLOW}🔗 برای اطمینان کامل، نتیجه را در سایت زیر بررسی کنید:${NC}"
echo -e "${BLUE}https://www.dnsleaktest.com/${NC}"
