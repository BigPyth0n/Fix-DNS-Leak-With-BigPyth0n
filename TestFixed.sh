cat > dns-test.sh <<'EOF'
#!/bin/bash
set -euo pipefail
echo "== DNS wiring =="
echo -n "/etc/resolv.conf -> "; readlink -f /etc/resolv.conf
echo

echo "== cloudflared socket =="
ss -tulnp | grep -E "127\.0\.0\.1:53" || echo "cloudflared NOT listening on 127.0.0.1:53"
echo

echo "== dig direct to local resolver =="
dig +time=2 +tries=1 +short @127.0.0.1 google.com || echo "dig @127.0.0.1 failed"
echo

echo "== system path resolution =="
dig +time=2 +tries=1 +short google.com || echo "dig system path failed"
echo

echo "== whoami via Cloudflare (TXT) =="
echo -n "127.0.0.1 -> "; dig +short TXT whoami.cloudflare @127.0.0.1 || true
echo -n "1.1.1.1   -> "; dig +short TXT whoami.cloudflare @1.1.1.1 || true
echo

echo "== resolvectl summary =="
resolvectl status | sed -n '1,120p'
echo

echo "== dnsleaktest style lookups =="
for i in {1..5}; do
  echo -n "test$i: "
  dig +short @127.0.0.1 test$i.dnsleaktest.com || true
done
EOF
chmod +x dns-test.sh
./dns-test.sh
