#!/usr/bin/env bash
# gen-link.sh — генерация vless:// ссылок для variant-b
# Вызывается через tools/gen-link.sh variant-b [--qr] [--save]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

VARS="${SCRIPT_DIR}/vars.env"
[[ -f "$VARS" ]] || { echo "ERROR: $VARS не найден"; exit 1; }
set -a; source "$VARS"; set +a

for v in UUID_REALITY UUID_WS PUB_KEY SHORT_ID REALITY_DOMAIN SERVER_IP DOMAIN WS_PATH; do
    [[ -n "${!v:-}" ]] || { echo "ERROR: $v не задан в vars.env"; exit 1; }
done

WS_PATH_ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${WS_PATH}', safe='/'))")

LINK_REALITY="vless://${UUID_REALITY}@${SERVER_IP}:443"
LINK_REALITY+="?security=reality"
LINK_REALITY+="&encryption=none"
LINK_REALITY+="&pbk=${PUB_KEY}"
LINK_REALITY+="&fp=chrome"
LINK_REALITY+="&type=tcp"
LINK_REALITY+="&flow=xtls-rprx-vision"
LINK_REALITY+="&sni=${REALITY_DOMAIN}"
LINK_REALITY+="&sid=${SHORT_ID}"
LINK_REALITY+="&spx=%2F"
LINK_REALITY+="#variant-b-reality"

LINK_WS="vless://${UUID_WS}@${DOMAIN}:443"
LINK_WS+="?security=tls"
LINK_WS+="&encryption=none"
LINK_WS+="&type=ws"
LINK_WS+="&path=${WS_PATH_ENCODED}"
LINK_WS+="&sni=${DOMAIN}"
LINK_WS+="#variant-b-ws-cdn"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  variant-b: Nginx stream SNI routing"
echo "  Server:    ${SERVER_IP}:443  (via Nginx stream)"
echo "  Reality:   → ${SERVER_IP}:${REALITY_INBOUND_PORT:-8443}"
echo "  WS+TLS:    → ${DOMAIN}:${NGINX_HTTPS_PORT:-7443}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "── VLESS+TCP+Vision+Reality (прямой клиент) ──"
echo "$LINK_REALITY"
echo
echo "── VLESS+WS+TLS (CDN-совместимый) ───────────"
echo "$LINK_WS"
echo

QR=0; SAVE=0
for arg in "$@"; do
    [[ "$arg" == "--qr"   ]] && QR=1
    [[ "$arg" == "--save" ]] && SAVE=1
done

if (( QR )); then
    if command -v qrencode &>/dev/null; then
        echo "QR: Reality"
        qrencode -t ANSIUTF8 "$LINK_REALITY"
        echo "QR: WS+TLS"
        qrencode -t ANSIUTF8 "$LINK_WS"
    else
        echo "(установи qrencode для QR-кодов)"
    fi
fi

if (( SAVE )); then
    NOTES_DIR="${REPO_ROOT}/notes"
    mkdir -p "$NOTES_DIR"
    OUT="${NOTES_DIR}/variant-b-links.txt"
    printf "%s\n%s\n" "$LINK_REALITY" "$LINK_WS" > "$OUT"
    echo "Сохранено: $OUT"
fi
