#!/usr/bin/env bash
# gen-keys.sh — генерация Reality ключей и UUID (вариант-aware)
# Использование:
#   ./tools/gen-keys.sh                    — вывод всех значений на экран
#   ./tools/gen-keys.sh --write variant-a  — записать в scenarios/variant-a/vars.env
#   ./tools/gen-keys.sh --write variant-b  — UUID_REALITY + UUID_WS + x25519
#   ./tools/gen-keys.sh --write variant-c   — UUID_VLESS + UUID_VMESS (без x25519)
#   ./tools/gen-keys.sh --write variant-c2  — UUID + TR_PASSWORD + SS_PASSWORD
#   ./tools/gen-keys.sh --write variant-d  — только UUID (TLS, не Reality)
#
# Имена переменных в vars.env по вариантам:
#   variant-a:  UUID, PRIV_KEY, PUB_KEY, SHORT_ID
#   variant-b:  UUID_REALITY, UUID_WS, PRIV_KEY, PUB_KEY, SHORT_ID
#   variant-c:  UUID_VLESS, UUID_VMESS
#   variant-d:  UUID
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

XRAY_BIN="${XRAY_BIN:-$(command -v xray 2>/dev/null || echo "")}"
[[ -x "$XRAY_BIN" ]] || {
    echo "ERROR: xray не найден. Установи xray или укажи XRAY_BIN=/path/to/xray"
    exit 1
}

keypair="$("$XRAY_BIN" x25519 2>/dev/null)"
PRIV_KEY="$(echo "$keypair" | awk '/Private/ {print $NF}')"
PUB_KEY="$(echo  "$keypair" | awk '/Public/  {print $NF}')"
UUID_1="$("$XRAY_BIN" uuid 2>/dev/null)"
UUID_2="$("$XRAY_BIN" uuid 2>/dev/null)"
SHORT_ID="$(openssl rand -hex 8)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  UUID (1):  $UUID_1"
echo "  UUID (2):  $UUID_2"
echo "  PRIV_KEY:  $PRIV_KEY"
echo "  PUB_KEY:   $PUB_KEY"
echo "  SHORT_ID:  $SHORT_ID"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "${1:-}" == "--write" && -n "${2:-}" ]]; then
    VAR="${2}"
    VARS="${REPO_ROOT}/scenarios/${VAR}/vars.env"
    [[ -f "$VARS" ]] || {
        echo "ERROR: $VARS не найден — сначала запусти: make init VAR=${VAR}"
        exit 1
    }

    case "$VAR" in
        variant-a)
            sed -i \
                -e "s|^UUID=.*|UUID=${UUID_1}|" \
                -e "s|^PRIV_KEY=.*|PRIV_KEY=${PRIV_KEY}|" \
                -e "s|^PUB_KEY=.*|PUB_KEY=${PUB_KEY}|" \
                -e "s|^SHORT_ID=.*|SHORT_ID=${SHORT_ID}|" \
                "$VARS"
            echo "  variant-a: UUID, PRIV_KEY, PUB_KEY, SHORT_ID → $VARS"
            ;;
        variant-b)
            sed -i \
                -e "s|^UUID_REALITY=.*|UUID_REALITY=${UUID_1}|" \
                -e "s|^UUID_WS=.*|UUID_WS=${UUID_2}|" \
                -e "s|^PRIV_KEY=.*|PRIV_KEY=${PRIV_KEY}|" \
                -e "s|^PUB_KEY=.*|PUB_KEY=${PUB_KEY}|" \
                -e "s|^SHORT_ID=.*|SHORT_ID=${SHORT_ID}|" \
                "$VARS"
            echo "  variant-b: UUID_REALITY, UUID_WS, PRIV_KEY, PUB_KEY, SHORT_ID → $VARS"
            ;;
        variant-c)
            sed -i \
                -e "s|^UUID_VLESS=.*|UUID_VLESS=${UUID_1}|" \
                -e "s|^UUID_VMESS=.*|UUID_VMESS=${UUID_2}|" \
                "$VARS"
            echo "  variant-c: UUID_VLESS, UUID_VMESS → $VARS"
            echo "  (x25519 не нужен — Reality не используется)"
            ;;
        variant-c2)
            TR_PASS="$(openssl rand -hex 16)"
            SS_PASS="$(openssl rand -base64 16 | tr -d '\n')"
            sed -i \
                -e "s|^UUID=.*|UUID=${UUID_1}|" \
                -e "s|^TR_PASSWORD=.*|TR_PASSWORD=${TR_PASS}|" \
                -e "s|^SS_PASSWORD=.*|SS_PASSWORD=${SS_PASS}|" \
                "$VARS"
            echo "  variant-c2: UUID, TR_PASSWORD, SS_PASSWORD → $VARS"
            echo "  SS_PASSWORD: 16-byte base64 key (2022-blake3-aes-128-gcm)"
            ;;
        variant-d)
            sed -i \
                -e "s|^UUID=.*|UUID=${UUID_1}|" \
                "$VARS"
            echo "  variant-d: UUID → $VARS"
            echo "  (x25519 не нужен — Self-SNI использует TLS, не Reality)"
            ;;
        *)
            echo "  [!] Неизвестный вариант '${VAR}' — применяем схему variant-a"
            sed -i \
                -e "s|^UUID=.*|UUID=${UUID_1}|" \
                -e "s|^PRIV_KEY=.*|PRIV_KEY=${PRIV_KEY}|" \
                -e "s|^PUB_KEY=.*|PUB_KEY=${PUB_KEY}|" \
                -e "s|^SHORT_ID=.*|SHORT_ID=${SHORT_ID}|" \
                "$VARS"
            echo "  Записано в: $VARS"
            ;;
    esac
fi
