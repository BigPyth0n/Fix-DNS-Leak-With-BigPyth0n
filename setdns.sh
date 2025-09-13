#!/bin/bash
# DoH with cloudflared + full system upgrade + nano/tmux
# v3.4-final (Alisa)
# Changelog:
#   v3.4: Added automatic hostname resolution to fix sudo errors.

set -euo pipefail

# ── رنگ‌ها ─────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'; NC='\033[0m'

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ لطفاً با sudo یا کاربر root اجرا کنید.${NC}"; exit 1
  fi
}

# (NEW) تابع اصلاح رزولوشن هاست‌نیم
resolve_hostname() {
    echo -e "${YELLOW}🔎 بررسی و اصلاح رزولوشن هاست‌نیم محلی...${NC}"
    local HOSTNAME
    HOSTNAME=$(hostname)
    if ! grep -q "127.0.0.1.*$HOSTNAME" /etc/hosts; then
        sed -i "/^127\.0\.0\.1/ s/$/ $HOSTNAME/" /etc/hosts
        echo -e "${GREEN}✅ هاست‌نیم '$HOSTNAME' برای جلوگیری از خطای sudo به فایل hosts اضافه شد.${NC}"
    else
        echo -e "${GREEN}✅ هاست‌نیم از قبل به درستی در فایل hosts تنظیم شده است.${NC}"
    fi
}

# بکاپ‌گیر ساده (در صورت وجود فایل)
backup_files=()
bak() { [[ -f "$1" ]] && cp -a "$1" "$1.bak.$(date +%Y%m%d%H%M%S)" && backup_files+=("$1") || true; }

rollback() {
  echo -e "${YELLOW}↩️ در حال بازگردانی بکاپ‌ها...${NC}"
  for f in "${backup_files[@]}"; do
    local lastbak; lastbak=$(ls -1 "$f".bak.* 2>/dev/null | tail -n1 || true)
    [[ -n "${lastbak:-}" ]] && cp -af "$lastbak" "$f" || true
  done
}

trap 'echo -e "\n${RED}⚠️ اجرای اسکریپت شکست خورد. برای بازگشت دستی از بکاپ‌های *.bak.* استفاده کنید.${NC}"' ERR

main() {
  require_root
  echo -e "${BLUE}=== نصب و پیکربندی DoH با cloudflared (v3.4-final) ===${NC}"

  # (NEW) فراخوانی تابع اصلاح هاست‌نیم در ابتدای اجرا
  resolve_hostname

  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  # ── 0) پیش‌نیاز کوچک: اگر شبکه‌ات DNS نداره، یک resolv.conf موقت بذار ──
  if ! ping -c1 -W1 1.1.1.1 >/dev/null 2>&1; then
    echo -e "${YELLOW}🌐 اتصال ICMP به 1.1.1.1 برقرار نیست؛ ادامه می‌دهیم...${NC}"
  fi
  if ! getent hosts cloudflare.com >/dev/null 2>&1; then
    echo -e "${YELLOW}🩹 DNS موقت برای بازیابی اینترنت...${NC}"
    printf "nameserver 1.1.1.1\noptions edns0 trust-ad\n" > /etc/resolv.conf
  fi

  # ── 1) آپدیت/آپگرید کامل سیستم ──
  echo -e "${YELLOW}🔄 آپدیت و ارتقای کل سیستم...${NC}"
  apt-get update -qq
  apt-get upgrade -y -qq -o Dpkg::Options::=--force-confold
  apt-get dist-upgrade -y -qq -o Dpkg::Options::=--force-confold
  apt-get autoremove -y -qq

  # ── 2) حذف تداخل resolvconf (اگر نصب بود) ──
  if dpkg -l | grep -qw resolvconf; then
    echo -e "${YELLOW}🧹 حذف resolvconf برای جلوگیری از تداخل...${NC}"
    apt-get purge -y -qq resolvconf || true
  fi

  # ── 3) نصب ابزارها ──
  echo -e "${YELLOW}🧰 نصب پیش‌نیازها...${NC}"
  apt-get install -y -qq curl wget jq dnsutils net-tools lsb-release nano tmux

  # ── 4) (اصلاح شده) غیرفعال کردن DNSStubListener برای آزاد کردن پورت 53 ──
  echo -e "${YELLOW}⚙️ آزادسازی پورت 53 با غیرفعال کردن DNSStubListener...${NC}"
  bak /etc/systemd/resolved.conf
  # فقط DNSStubListener را غیرفعال می‌کنیم تا پورت آزاد شود
  sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
  systemctl restart systemd-resolved

  # ── 5) نصب cloudflared ──
  if ! command -v cloudflared >/dev/null 2>&1; then
    echo -e "${YELLOW}⬇️ نصب cloudflared...${NC}"
    ARCH=$(dpkg --print-architecture)
    URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
    wget -qO /tmp/cloudflared.deb "$URL"
    dpkg -i /tmp/cloudflared.deb
    rm -f /tmp/cloudflared.deb
  else
    echo -e "${GREEN}✅ cloudflared از قبل نصب است.${NC}"
  fi

  # ── 6) کانفیگ cloudflared ──
  echo -e "${YELLOW}⚙️ نوشتن config cloudflared...${NC}"
  install -d -m 0755 /etc/cloudflared
  cat > /etc/cloudflared/config.yml <<'YAML'
proxy-dns: true
proxy-dns-address: 127.0.0.1
proxy-dns-port: 53
upstream:
  - https://1.1.1.1/dns-query
  - https://1.0.0.1/dns-query
YAML

  # ── 7) سرویس systemd برای cloudflared ──
  echo -e "${YELLOW}🧩 ایجاد سرویس systemd...${NC}"
  CLOUDFLARED_BIN="$(command -v cloudflared)"
  cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflared DNS over HTTPS proxy
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=${CLOUDFLARED_BIN} --config /etc/cloudflared/config.yml
User=nobody
Restart=on-failure
RestartSec=3
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now cloudflared

  # ── 8) (اصلاح شده) پیکربندی نهایی systemd-resolved برای استفاده از cloudflared ──
  echo -e "${YELLOW}🧭 پیکربندی نهایی systemd-resolved برای استفاده از 127.0.0.1...${NC}"
  cat > /etc/systemd/resolved.conf <<'EOF'
[Resolve]
DNS=127.0.0.1
Domains=~.
DNSStubListener=no
FallbackDNS=
EOF
  # این لینک باید در انتها ساخته شود
  ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
  systemctl restart systemd-resolved

  # ── 9) تست‌ها ──
  echo -e "${BLUE}🔎 تست سرویس‌ها...${NC}"
  sleep 2

  if ! ss -tulnp | grep -qE "127\.0\.0\.1:53"; then
    echo -e "${RED}❌ cloudflared روی 127.0.0.1:53 گوش نمی‌دهد.${NC}"
    journalctl -u cloudflared --no-pager -n 200 || true
    rollback; exit 1
  fi
  echo -e "${GREEN}✅ cloudflared روی 127.0.0.1:53 فعال است.${NC}"

  dig +time=2 +tries=1 +short @127.0.0.1 cloudflare.com >/dev/null || {
    echo -e "${RED}❌ پاسخ DNS از 127.0.0.1 دریافت نشد.${NC}"
    journalctl -u cloudflared --no-pager -n 200 || true
    rollback; exit 1
  }

  dig +time=2 +tries=1 +short google.com >/dev/null || {
    echo -e "${RED}❌ مسیر رزولوشن سیستم مشکل دارد.${NC}"
    resolvectl status | sed -n '1,160p' || true
    exit 1
  }

  ACTIVE_DNS=$(dig google.com | awk '/SERVER:/{print $3}' | awk -F'#' '{print $1}')
  echo -e "${GREEN}✅ DNS فعال از دید dig: ${ACTIVE_DNS}${NC}"

  echo -e "${GREEN}🎉 همه‌چیز آماده است. سیستم upgrade شد، nano و tmux نصب شدند، و DoH فعال است.${NC}"
  echo -e "${YELLOW}برای اطمینان نهایی، نتیجه را در dnsleaktest.com چک کن.${NC}"
}

main "$@"
