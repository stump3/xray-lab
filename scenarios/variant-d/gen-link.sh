#!/usr/bin/env bash
# gen-link.sh — генерация vless:// ссылки для variant-d (VLESS+TCP+TLS+Vision)
# Вызывается через tools/gen-link.sh variant-d [--qr] [--save]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

VARS="${SCRIPT_DIR}/vars.env"
[[ -f "$VARS" ]] || { echo "ERROR: $VARS не найден"; exit 1; }
set -a; source "$VARS"; set +a

for v in UUID DOMAIN SERVER_IP; do
    [[ -n "${!v:-}" ]] || { echo "ERROR: $v не задан в vars.env"; exit 1; }
done

LINK="vless://${UUID}@${DOMAIN}:443"
LINK+="?security=tls"
LINK+="&encryption=none"
LINK+="&fp=chrome"
LINK+="&alpn=http%2F1.1"
LINK+="&type=tcp"
LINK+="&flow=xtls-rprx-vision"
LINK+="&spx=%2F"
LINK+="#variant-d-selfsni"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  variant-d: Self-SNI (VLESS+TCP+TLS+Vision)"
echo "  Server:  ${DOMAIN}:443  (IP: ${SERVER_IP})"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "── VLESS+TCP+TLS+Vision ──────────────────────"
echo "$LINK"
echo

QR=0; SAVE=0
for arg in "$@"; do
    [[ "$arg" == "--qr"   ]] && QR=1
    [[ "$arg" == "--save" ]] && SAVE=1
done

if (( QR )); then
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$LINK"
    else
        echo "(установи qrencode для QR-кода)"
    fi
fi

if (( SAVE )); then
    NOTES_DIR="${REPO_ROOT}/notes"
    mkdir -p "$NOTES_DIR"
    OUT="${NOTES_DIR}/variant-d-links.txt"
    echo "$LINK" > "$OUT"
    echo "Сохранено: $OUT"
fi
