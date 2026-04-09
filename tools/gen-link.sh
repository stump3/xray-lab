#!/usr/bin/env bash
# gen-link.sh — генерация subscription ссылок для любого варианта
# Использование:
#   ./tools/gen-link.sh variant-a             — ссылка на экран
#   ./tools/gen-link.sh variant-a --qr        — ссылка + QR-код
#   ./tools/gen-link.sh variant-a --save      — сохранить в notes/
#   ./tools/gen-link.sh variant-b --qr --save — оба флага вместе
#
# Диспетчер: делегирует в scenarios/<VAR>/gen-link.sh
# Для variant-a логика встроена здесь (совместимость с оригинальной версией).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VAR="${1:-}"
[[ -n "$VAR" ]] || { echo "Использование: $0 <variant> [--qr] [--save]"; exit 1; }

shift  # убираем VAR из аргументов, остаток передаём в сценарный gen-link.sh

SCENARIO_LINK="${REPO_ROOT}/scenarios/${VAR}/gen-link.sh"

# Если у сценария есть собственный gen-link.sh — делегируем
if [[ -x "$SCENARIO_LINK" ]]; then
    exec bash "$SCENARIO_LINK" "$@"
fi

# ── Встроенная логика для variant-a (оригинальная) ────────────────────────────

if [[ "$VAR" != "variant-a" ]]; then
    echo "ERROR: scenarios/${VAR}/gen-link.sh не найден"
    echo "       Создай файл или добавь логику в tools/gen-link.sh"
    exit 1
fi

VARS="${REPO_ROOT}/scenarios/${VAR}/vars.env"
[[ -f "$VARS" ]] || { echo "ERROR: $VARS не найден"; exit 1; }
set -a; source "$VARS"; set +a

for v in UUID PUB_KEY SHORT_ID REALITY_DOMAIN SERVER_IP XRAY_PORT XHTTP_PATH; do
    [[ -n "${!v:-}" ]] || { echo "ERROR: $v не задан в vars.env"; exit 1; }
done

PATH_ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${XHTTP_PATH}', safe='/'))")
PROFILE_NAME="variant-a-xhttp-reality"

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

for arg in "$@"; do
    if [[ "$arg" == "--qr" ]]; then
        command -v qrencode &>/dev/null \
            && qrencode -t ANSIUTF8 "$LINK" \
            || echo "(установи qrencode для QR-кода)"
    fi
    if [[ "$arg" == "--save" ]]; then
        mkdir -p "${REPO_ROOT}/notes"
        echo "$LINK" > "${REPO_ROOT}/notes/${VAR}-link.txt"
        echo "  Сохранено: notes/${VAR}-link.txt"
    fi
done
