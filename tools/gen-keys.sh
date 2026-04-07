#!/usr/bin/env bash
# gen-keys.sh — генерация Reality ключей и UUID
# Использование:
#   ./tools/gen-keys.sh                    — вывод на экран
#   ./tools/gen-keys.sh --write variant-a  — записать в scenarios/variant-a/vars.env
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Проверяем наличие xray
XRAY_BIN="${XRAY_BIN:-$(command -v xray 2>/dev/null || echo "")}"
[[ -x "$XRAY_BIN" ]] || {
    echo "ERROR: xray не найден. Установи xray или укажи XRAY_BIN=/path/to/xray"
    exit 1
}

# Генерация
keypair="$("$XRAY_BIN" x25519 2>/dev/null)"
PRIV_KEY="$(echo "$keypair" | awk '/Private/ {print $NF}')"
PUB_KEY="$(echo  "$keypair" | awk '/Public/  {print $NF}')"
UUID="$("$XRAY_BIN" uuid 2>/dev/null)"
SHORT_ID="$(openssl rand -hex 8)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  UUID:      $UUID"
echo "  PRIV_KEY:  $PRIV_KEY"
echo "  PUB_KEY:   $PUB_KEY"
echo "  SHORT_ID:  $SHORT_ID"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Опционально: записать в vars.env нужного варианта
if [[ "${1:-}" == "--write" && -n "${2:-}" ]]; then
    VARS="${REPO_ROOT}/scenarios/${2}/vars.env"
    [[ -f "$VARS" ]] || {
        echo "ERROR: $VARS не найден — сначала скопируй vars.env.example → vars.env"
        exit 1
    }

    # Обновляем только нужные строки, остальное не трогаем
    sed -i \
        -e "s|^UUID=.*|UUID=${UUID}|" \
        -e "s|^PRIV_KEY=.*|PRIV_KEY=${PRIV_KEY}|" \
        -e "s|^PUB_KEY=.*|PUB_KEY=${PUB_KEY}|" \
        -e "s|^SHORT_ID=.*|SHORT_ID=${SHORT_ID}|" \
        "$VARS"

    echo "  Записано в: $VARS"
fi
