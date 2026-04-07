#!/usr/bin/env bash
# gen-link.sh — генерация vless:// ссылки для variant-a (VLESS+XHTTP+Reality)
# Использование:
#   ./tools/gen-link.sh variant-a             — вывод ссылки
#   ./tools/gen-link.sh variant-a --qr        — ссылка + QR-код в терминале
#   ./tools/gen-link.sh variant-a --save      — сохранить в notes/variant-a-link.txt
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VAR="${1:-}"
[[ -n "$VAR" ]] || { echo "Укажи вариант: $0 variant-a"; exit 1; }

VARS="${REPO_ROOT}/scenarios/${VAR}/vars.env"
[[ -f "$VARS" ]] || { echo "ERROR: $VARS не найден"; exit 1; }

set -a; source "$VARS"; set +a

# Проверяем обязательные переменные
for v in UUID PUB_KEY SHORT_ID REALITY_DOMAIN SERVER_IP XRAY_PORT XHTTP_PATH; do
    [[ -n "${!v:-}" ]] || { echo "ERROR: $v не задан в vars.env"; exit 1; }
done

# Кодируем path для URL (убираем ведущий слэш, потом добавим)
PATH_ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${XHTTP_PATH}', safe='/'))")

# Имя профиля
PROFILE_NAME="variant-a-xhttp-reality"

# Собираем vless:// ссылку
LINK="vless://${UUID}@${SERVER_IP}:${XRAY_PORT}"
LINK+="?security=reality"
LINK+="&encryption=none"
LINK+="&pbk=${PUB_KEY}"
LINK+="&fp=chrome"
LINK+="&type=xhttp"
LINK+="&path=${PATH_ENCODED}"
LINK+="&sni=${REALITY_DOMAIN}"
LINK+="&sid=${SHORT_ID}"
LINK+="&spx=%2F"
LINK+="#${PROFILE_NAME}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Profile: ${PROFILE_NAME}"
echo "  Server:  ${SERVER_IP}:${XRAY_PORT}"
echo "  Decoy:   ${REALITY_DOMAIN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "$LINK"
echo

# QR-код
if [[ "${2:-}" == "--qr" || "${3:-}" == "--qr" ]]; then
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$LINK"
    else
        echo "(установи qrencode для QR-кода)"
    fi
fi

# Сохранение
if [[ "${2:-}" == "--save" || "${3:-}" == "--save" ]]; then
    NOTES_DIR="${REPO_ROOT}/notes"
    mkdir -p "$NOTES_DIR"
    OUT="${NOTES_DIR}/${VAR}-link.txt"
    echo "$LINK" > "$OUT"
    echo "  Сохранено: $OUT"
fi
