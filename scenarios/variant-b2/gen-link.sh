#!/usr/bin/env bash
# gen-link.sh — генерация ссылок для variant-b2
# Reality + VLESS+WS+TLS + Hysteria2
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

VARS="${SCRIPT_DIR}/vars.env"
[[ -f "$VARS" ]] || { echo "ERROR: $VARS не найден"; exit 1; }
set -a; source "$VARS"; set +a

for v in UUID_REALITY UUID_WS PUB_KEY SHORT_ID REALITY_DOMAIN SERVER_IP DOMAIN WS_PATH H2_PASSWORD H2_DOMAIN; do
    [[ -n "${!v:-}" ]] || { echo "ERROR: $v не задан в vars.env"; exit 1; }
done

urlencode() {
    python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe='/'))" "$1"
}

# ── 1. VLESS + Vision + Reality ───────────────────────────────────────────────
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
LINK_REALITY+="#B2-Reality"

# ── 2. VLESS + WebSocket + TLS (CDN) ──────────────────────────────────────────
LINK_WS="vless://${UUID_WS}@${DOMAIN}:443"
LINK_WS+="?security=tls"
LINK_WS+="&encryption=none"
LINK_WS+="&type=ws"
LINK_WS+="&path=$(urlencode "${WS_PATH}")"
LINK_WS+="&sni=${DOMAIN}"
LINK_WS+="&fp=chrome"
LINK_WS+="#B2-WS-CDN"

# ── 3. Hysteria2 ───────────────────────────────────────────────────────────────
LINK_H2="hysteria2://${H2_PASSWORD}@${H2_DOMAIN}:443"
LINK_H2+="?insecure=0"
LINK_H2+="&sni=${H2_DOMAIN}"
LINK_H2+="#B2-Hysteria2"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  variant-b2: Nginx stream SNI routing + Hysteria2"
echo "  Server:     ${SERVER_IP}:443"
echo "  Reality →   ${REALITY_DOMAIN}  (прямой клиент)"
echo "  WS+TLS  →   ${DOMAIN}          (CDN-совместимый)"
echo "  H2      →   ${H2_DOMAIN}:443   (UDP)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "── 1. VLESS + Vision + Reality ───────────────────"
echo "$LINK_REALITY"
echo
echo "── 2. VLESS + WS + TLS (CDN) ─────────────────────"
echo "$LINK_WS"
echo
echo "── 3. Hysteria2 (UDP:443) ─────────────────────────"
echo "$LINK_H2"
echo

QR=0; SAVE=0
for arg in "$@"; do
    [[ "$arg" == "--qr"   ]] && QR=1
    [[ "$arg" == "--save" ]] && SAVE=1
done

if (( QR )) && command -v qrencode &>/dev/null; then
    echo "QR: Reality"
    qrencode -t ANSIUTF8 "$LINK_REALITY"
    echo "QR: WS+TLS"
    qrencode -t ANSIUTF8 "$LINK_WS"
    echo "QR: Hysteria2"
    qrencode -t ANSIUTF8 "$LINK_H2"
elif (( QR )); then
    echo "(установи qrencode для QR-кодов)"
fi

if (( SAVE )); then
    mkdir -p "${REPO_ROOT}/notes"
    OUT="${REPO_ROOT}/notes/variant-b2-links.txt"
    printf "%s\n%s\n%s\n" "$LINK_REALITY" "$LINK_WS" "$LINK_H2" > "$OUT"
    echo "Сохранено: $OUT"
fi
