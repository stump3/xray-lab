#!/usr/bin/env bash
# check-domain.sh — проверяет домен на пригодность для Reality decoy
# Критерии: без Cloudflare, TLS 1.3, HTTP/2
# Использование:
#   ./tools/check-domain.sh www.microsoft.com
#   ./tools/check-domain.sh apple.com dl.google.com addons.mozilla.org
set -euo pipefail

TIMEOUT=8
PASS=0; FAIL=0

ok()   { echo "  ✓ $*"; (( PASS++ )) || true; }
fail() { echo "  ✗ $*"; (( FAIL++ )) || true; }

check_domain() {
    local domain="$1"
    echo
    echo "── ${domain} ─────────────────────────────────"

    # 1. Не Cloudflare
    local headers
    headers=$(curl -fsSL -I --max-time "$TIMEOUT" "https://$domain" 2>/dev/null \
        | tr '[:upper:]' '[:lower:]') || headers=""
    if echo "$headers" | grep -q "cf-ray:"; then
        fail "Cloudflare — Reality несовместима"
    else
        ok "Не использует Cloudflare"
    fi

    # 2. TLS 1.3
    local code
    code=$(curl -fsSL --tlsv1.3 --tls-max 1.3 --max-time "$TIMEOUT" \
        -o /dev/null -w "%{http_code}" "https://$domain" 2>/dev/null) || code=0
    if [[ "$code" =~ ^[1-9][0-9]{2}$ ]]; then
        ok "TLS 1.3 поддерживается (HTTP ${code})"
    else
        fail "TLS 1.3 не поддерживается"
    fi

    # 3. HTTP/2
    if curl -fsSL --http2 -v --max-time "$TIMEOUT" \
        -o /dev/null "https://$domain" 2>&1 | grep -q "< HTTP/2"; then
        ok "HTTP/2 поддерживается"
    else
        fail "HTTP/2 не поддерживается"
    fi

    # 4. Итог
    if (( FAIL == 0 )); then
        echo "  → ПОДХОДИТ для Reality"
    else
        echo "  → НЕ ПОДХОДИТ (${FAIL} проблем)"
    fi
    PASS=0; FAIL=0
}

[[ $# -gt 0 ]] || {
    echo "Использование: $0 <domain> [domain2] [domain3]"
    echo "Примеры:"
    echo "  $0 www.microsoft.com"
    echo "  $0 apple.com dl.google.com addons.mozilla.org"
    exit 1
}

for domain in "$@"; do
    check_domain "$domain"
done
echo
