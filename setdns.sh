#!/bin/bash
set -euo pipefail

# ── رنگ‌ها ─────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'; NC='\033[0m'

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ لطفاً با sudo یا کاربر root اجرا کنید.${NC}"; exit 1
  fi
}

backup_files=()
bak() { [[ -f "$1" ]] && cp -a "$1" "$1.bak.$(date +%Y%m%d%H%M%S)" && backup_files+=("$1"); }

rollback() {
  echo -e "${YELLOW}↩️ در حال بازگردانی بکاپ‌ها...${NC}"
  for f in "${backup_files[@]}"; do
    local lastbak
    lastbak=$(ls -1 "$f".bak.* 2>/dev/null | tail -n1 || true)
    if [[ -n "${lastbak:-}" ]]; then cp -af "$lastbak" "$f"; fi
  done
}

trap 'echo -e "\n${RED}⚠️ شکست خورد. برای بازگشت دستی از بکاپ‌های *.bak.* استفاده کنید.${NC}"' ERR

main() {
  require_root
  echo -e "${BLUE}=== نصب و پیکربندی DoH با cloudflared (v3.1) ===${NC}"

  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  echo -e "${YELLOW}🔄 به‌روزرسانی ایندکس پکیج‌ها...${NC}"
  apt-get update -qq

  # 1) حذف تداخل resolvconf (اگر نصب بود)
  if dpkg -l | grep -qw resolvconf; then
    echo -e "${YELLOW}🧹 حذف resolvconf برای جلوگیری از تداخل...${NC}"
    apt-get purge -y -qq resolvconf || true
  fi

  # 2) نصب ابزارهای لازم
  echo -e "${YELLOW}🧰 نصب پیش‌نیازها...${NC}"
  apt-get install -y -qq curl wget jq dnsutils net-tools lsb-release

  # 3) نصب cloudflared (اگر نبود)
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

  # 4) کانفیگ cloudflared
  echo -e "${YELLOW}⚙️ نوشتن config cloudflared...${NC}"
  install -d -m 0755 /etc/cloudflared
  cat > /etc/cloudflared/config.yml <<'YAML'
proxy-dns: true
proxy-dns-address: 127.0.0.1
proxy-dns-port: 53
upstream:
  - https://1.1.1.1/dns-query
  - https://1.0.0.1/dns-query
# گزینه‌های اختیاری:
# require-dnssec: true
YAML

  # 5) سرویس systemd برای cloudflared
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

  # 6) تنظیم systemd-resolved
  echo -e "${YELLOW}🧭 پیکربندی systemd-resolved...${NC}"
  bak /etc/systemd/resolved.conf
  cat > /etc/systemd/resolved.conf <<'EOF'
[Resolve]
DNS=127.0.0.1
Domains=~.
DNSStubListener=no
FallbackDNS=
EOF

  # مطمئن شو resolv.conf به systemd اشاره دارد
  ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

  systemctl restart systemd-resolved

  # 7) تست‌ها
  echo -e "${BLUE}🔎 تست سرویس‌ها...${NC}"
  sleep 2
  if ! ss -tulnp | grep -qE "127\.0\.0\.1:53"; then
    echo -e "${RED}❌ cloudflared روی 127.0.0.1:53 گوش نمی‌دهد.${NC}"
    journalctl -u cloudflared --no-pager -n 200 || true
    rollback; exit 1
  fi

  echo -e "${YELLOW}🧪 dig مستقیم به 127.0.0.1...${NC}"
  if ! dig +time=2 +tries=1 +short @127.0.0.1 cloudflare.com >/dev/null; then
    echo -e "${RED}❌ پاسخ از 127.0.0.1 دریافت نشد.${NC}"
    journalctl -u cloudflared --no-pager -n 200 || true
    rollback; exit 1
  fi

  echo -e "${YELLOW}🧪 رزولوشن از مسیر سیستم...${NC}"
  dig +time=2 +tries=1 +short google.com >/dev/null

  ACTIVE_DNS=$(dig google.com | awk '/SERVER:/{print $3}' | awk -F'#' '{print $1}')
  echo -e "${GREEN}✅ DNS فعال از دید dig: ${ACTIVE_DNS}${NC}"

  if [[ "${ACTIVE_DNS}" != "127.0.0.1" ]]; then
    echo -e "${RED}⚠️ هشدار: انتظار داشتیم 127.0.0.1 باشد.${NC}"
    resolvectl status | sed -n '1,120p' || true
    echo -e "${YELLOW}اما اگر همه‌چیز کار می‌کند، ممکن است dig از کش/مسیریابی متفاوتی گزارش بدهد.${NC}"
  fi

  echo -e "${GREEN}🎉 همه‌چیز آماده است. DNS از طریق DoH روی cloudflared تنظیم شد.${NC}"
  echo -e "${YELLOW}برای اطمینان: dnsleaktest.com را اجرا/بازبینی کن.${NC}"
}

main "$@"
