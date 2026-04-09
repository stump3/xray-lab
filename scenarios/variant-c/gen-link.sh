#!/usr/bin/env bash
# gen-link.sh — генерация vless:// и vmess:// ссылок для variant-c (fallbacks)
# Вызывается через tools/gen-link.sh variant-c [--qr] [--save]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

VARS="${SCRIPT_DIR}/vars.env"
[[ -f "$VARS" ]] || { echo "ERROR: $VARS не найден"; exit 1; }
set -a; source "$VARS"; set +a

for v in UUID_VLESS UUID_VMESS DOMAIN; do
    [[ -n "${!v:-}" ]] || { echo "ERROR: $v не задан в vars.env"; exit 1; }
done

VLESS_PATH_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${VLESS_WS_PATH}', safe='/'))")
VMESS_PATH_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${VMESS_WS_PATH}', safe='/'))")

LINK_VLESS="vless://${UUID_VLESS}@${DOMAIN}:443"
LINK_VLESS+="?security=tls"
LINK_VLESS+="&encryption=none"
LINK_VLESS+="&type=ws"
LINK_VLESS+="&path=${VLESS_PATH_ENC}"
LINK_VLESS+="&sni=${DOMAIN}"
LINK_VLESS+="&fp=chrome"
LINK_VLESS+="#variant-c-vless-ws"

# VMess: base64-кодированный JSON
VMESS_JSON=$(python3 -c "
import json, base64
obj = {
    'v': '2',
    'ps': 'variant-c-vmess-ws',
    'add': '${DOMAIN}',
    'port': '443',
    'id': '${UUID_VMESS}',
    'aid': '0',
    'net': 'ws',
    'type': 'none',
    'host': '${DOMAIN}',
    'path': '${VMESS_WS_PATH}',
    'tls': 'tls',
    'sni': '${DOMAIN}',
    'fp': 'chrome'
}
print('vmess://' + base64.b64encode(json.dumps(obj).encode()).decode())
")
LINK_VMESS="$VMESS_JSON"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  variant-c: Xray native fallbacks (All-in-One)"
echo "  Server:  ${DOMAIN}:443  (Xray, TLS)"
echo "  Reality: недоступна в этой схеме"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "── VLESS+WS+TLS (CDN-совместимый) ───────────"
echo "$LINK_VLESS"
echo
echo "── VMess+WS+TLS (CDN-совместимый) ───────────"
echo "$LINK_VMESS"
echo

QR=0; SAVE=0
for arg in "$@"; do
    [[ "$arg" == "--qr"   ]] && QR=1
    [[ "$arg" == "--save" ]] && SAVE=1
done

if (( QR )); then
    if command -v qrencode &>/dev/null; then
        echo "QR: VLESS+WS+TLS"
        qrencode -t ANSIUTF8 "$LINK_VLESS"
        echo "QR: VMess+WS+TLS"
        qrencode -t ANSIUTF8 "$LINK_VMESS"
    else
        echo "(установи qrencode для QR-кодов)"
    fi
fi

if (( SAVE )); then
    NOTES_DIR="${REPO_ROOT}/notes"
    mkdir -p "$NOTES_DIR"
    OUT="${NOTES_DIR}/variant-c-links.txt"
    printf "%s\n%s\n" "$LINK_VLESS" "$LINK_VMESS" > "$OUT"
    echo "Сохранено: $OUT"
fi
