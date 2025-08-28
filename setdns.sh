#!/bin/bash

#================================================================================
# اسکریپت بهینه‌سازی و ضد نشت DNS برای سرورهای لینوکس (مبتنی بر دبیان/اوبونتو)
# برنامه‌نویس اصلی: Big
# بازبینی و بهینه‌سازی: Alisa
# نسخه: 2.7
#
# این اسکریپت سیستم را به‌روز می‌کند، و
# با استفاده از cloudflared یک پراکسی امن DNS-over-HTTPS راه‌اندازی می‌کند
# تا تمام ترافیک DNS از یک نقطه واحد و امن (با استفاده از DNSهای Cloudflare) عبور کند.
#
# این نسخه برای رفع مشکل قطعی DNS در زمان دانلود، حذف مرحله تشخیص کشور و
# استفاده مستقیم از DNSهای Cloudflare، اصلاح شده است. همچنین تعاملات اضافی
# در حین نصب پکیج‌ها و مدیریت needrestart حذف شده و اطمینان از فعال بودن cloudflared
# قبل از تغییر پیکربندی سیستم DNS بهبود یافته است.
#================================================================================

# --- رنگ‌ها برای خروجی بهتر ---
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- تنظیمات عمومی برای اجرای غیرتعاملی ---
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a # Automatic restart for needrestart

# --- بررسی اجرای اسکریپت با دسترسی روت ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ لطفاً این اسکریپت را با دسترسی root یا با sudo اجرا کنید.${NC}"
  exit 1
fi

clear
echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}     🚀 اسکریپت حرفه‌ای ضد DNS Leak (نسخه 2.7) 🚀      ${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo -e "برنامه‌نویس اصلی: Big | بازبینی و بهبود: Alisa\n"

# --- بررسی اتصال اولیه به اینترنت ---
echo -e "${YELLOW}🌐 [بررسی اولیه] در حال بررسی اتصال اینترنت (پینگ به 8.8.8.8)...${NC}"
if ! ping -c 3 -W 2 8.8.8.8 > /dev/null 2>&1; then
    echo -e "${RED}❌ خطای اتصال به اینترنت! سرور نمی‌تواند به 8.8.8.8 پینگ کند. لطفاً اتصال شبکه را بررسی کنید.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ اتصال اینترنت اولیه برقرار است.${NC}"
# --- پایان بررسی اتصال اولیه ---


### گام 1: به‌روزرسانی کامل سیستم
echo -e "${YELLOW}🔄 [گام 1/7] در حال به‌روزرسانی کامل سیستم...${NC}"
apt-get update -qq && \
apt-get upgrade -y -qq -o Dpkg::Options::=--force-confold
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


### گام 3: تنظیم DNSهای Cloudflare به صورت پیش‌فرض
echo -e "\n${BLUE}🌍 [گام 3/7] استفاده مستقیم از DNSهای Cloudflare (1.1.1.1 و 1.0.0.1)...${NC}"
VALID_DNS=("1.1.1.1" "1.0.0.1")
echo -e "${GREEN}✅ لیست DNSهای نهایی: ${VALID_DNS[*]}${NC}"


### گام 4: نصب و پیکربندی cloudflared به عنوان سرویس
echo -e "\n${BLUE}🚀 [گام 4/7] نصب و پیکربندی Cloudflare Tunnel (cloudflared)...${NC}"
ARCH=$(dpkg --print-architecture)
GITHUB_HOST="raw.githubusercontent.com"
DOWNLOAD_PATH="/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"

echo -e "${YELLOW}⏳ در حال حل نام دامنه ${GITHUB_HOST} به صورت مستقیم...${NC}"
GITHUB_IP=$(dig @8.8.8.8 +short ${GITHUB_HOST} | head -n 1)

if [ -z "$GITHUB_IP" ] || [[ "$GITHUB_IP" == *[!0-9.]* ]]; then # Check if IP is valid
    echo -e "${RED}❌ خطای حل نام دامنه ${GITHUB_HOST} به IP. لطفاً مطمئن شوید که 8.8.8.8 قابل دسترسی است.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ ${GITHUB_HOST} به IP: ${GITHUB_IP} حل شد.${NC}"

DOWNLOAD_URL="https://${GITHUB_IP}${DOWNLOAD_PATH}"

# دانلود cloudflared با استفاده از IP و تنظیم Host header
echo -e "${YELLOW}⏳ در حال دانلود cloudflared از ${DOWNLOAD_URL} با Host header...${NC}"
wget -q --header="Host: ${GITHUB_HOST}" "$DOWNLOAD_URL" -O cloudflared.deb
DOWNLOAD_STATUS=$?

if [ "$DOWNLOAD_STATUS" -ne 0 ]; then
    echo -e "${RED}❌ خطای دانلود cloudflared (کد خطا: ${DOWNLOAD_STATUS}). لطفاً از اتصال به اینترنت مطمئن شوید و فایروال سرور را بررسی کنید.${NC}"
    exit 1
fi

# نصب cloudflared و بررسی موفقیت نصب
echo -e "${YELLOW}🔧 در حال نصب بسته cloudflared...${NC}"
if ! dpkg -i cloudflared.deb; then
    echo -e "${RED}❌ خطای نصب cloudflared. لطفاً خروجی بالا را بررسی کنید.${NC}"
    rm -f cloudflared.deb
    exit 1
fi
rm -f cloudflared.deb
echo -e "${GREEN}✅ بسته cloudflared با موفقیت نصب شد.${NC}"


# توقف سرویس در صورت اجرا بودن برای اعمال کانفیگ جدید
systemctl stop cloudflared >/dev/null 2>&1
pkill -f cloudflared >/dev/null 2>&1

# یافتن مسیر اجرایی cloudflared (ممکن است در /usr/bin یا /usr/local/bin باشد)
CLOUDFLARED_BIN=$(which cloudflared)
if [ -z "$CLOUDFLARED_BIN" ]; then
    # اگر which پیدا نکرد، مسیرهای رایج را امتحان کن
    if [ -f "/usr/bin/cloudflared" ]; then
        CLOUDFLARED_BIN="/usr/bin/cloudflared"
    elif [ -f "/usr/local/bin/cloudflared" ]; then
        CLOUDFLARED_BIN="/usr/local/bin/cloudflared"
    else
        echo -e "${RED}❌ فایل اجرایی cloudflared یافت نشد! نصب ناموفق بود یا در مسیری غیرمنتظره قرار گرفت.${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}ℹ️ فایل اجرایی cloudflared در: ${CLOUDFLARED_BIN} یافت شد.${NC}"


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
ExecStart=${CLOUDFLARED_BIN} --config /etc/cloudflared/config.yml
Restart=on-failure
RestartSec=10s
User=nobody # اجرای سرویس با کاربر غیرمجاز برای امنیت بیشتر

[Install]
WantedBy=multi-user.target
EOF

# فعال‌سازی و راه‌اندازی سرویس
systemctl daemon-reload
systemctl enable --now cloudflared
sleep 3 # زمان اولیه برای شروع سرویس

# بررسی اینکه آیا cloudflared بر روی 127.0.0.1:53 گوش می‌دهد
echo -e "${YELLOW}⏳ در حال بررسی فعال بودن Cloudflared روی پورت 53...${NC}"
CHECK_COUNT=0
MAX_CHECKS=10 # Try for 10 * 2 = 20 seconds
while ! ss -tulnp | grep -q "127.0.0.1:53"; do
    if [ "$CHECK_COUNT" -ge "$MAX_CHECKS" ]; then
        echo -e "${RED}❌ سرویس cloudflared روی پورت 53 فعال نشد! لطفاً وضعیت را با 'systemctl status cloudflared' و 'journalctl -xeu cloudflared' بررسی کنید.${NC}"
        exit 1
    fi
    sleep 2
    CHECK_COUNT=$((CHECK_COUNT+1))
done
echo -e "${GREEN}✅ سرویس cloudflared با موفقیت نصب و بر روی 127.0.0.1:53 فعال شد.${NC}"


### گام 5: تنظیم سیستم برای استفاده از پراکسی DNS محلی
echo -e "\n${BLUE}⚙️ [گام 5/7] تنظیم systemd-resolved برای استفاده از پراکسی محلی...${NC}"
# پشتیبان‌گیری از تنظیمات فعلی (اضافه شده)
cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak.$(date +%Y%m%d%H%M%S)
cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d%H%M%S)
echo -e "  ${YELLOW}ℹ️ از فایل‌های تنظیمات DNS پشتیبان‌گیری شد.${NC}"

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
sleep 2 # اطمینان از آماده بودن سرویس‌ها

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
