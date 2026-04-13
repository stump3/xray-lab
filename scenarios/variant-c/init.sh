#!/usr/bin/env bash
# init.sh — инициализация vars.env для variant-c (Xray native fallbacks)
# Использование:
#   bash scenarios/variant-c/init.sh           — интерактивно
#   bash scenarios/variant-c/init.sh --auto    — без вопросов
set -euo pipefail

AUTO=0
[[ "${1:-}" == "--auto" ]] && AUTO=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.env"

bold()  { echo -e "\033[1m$*\033[0m" > /dev/tty; }
ok()    { echo -e "  \033[32m[✓]\033[0m $*" > /dev/tty; }
info()  { echo -e "  \033[34m[·]\033[0m $*" > /dev/tty; }
warn()  { echo -e "  \033[33m[!]\033[0m $*" > /dev/tty; }

ask() {
    local label="$1" default="$2" value
    [[ -n "$default" ]] \
        && printf "  %-32s [%s]: " "$label" "$default" > /dev/tty \
        || printf "  %-32s : " "$label" > /dev/tty
    read -r value < /dev/tty
    echo "${value:-$default}"
}

detect_ip() {
    local ip=""
    for s in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
        ip="$(curl -fsSL --max-time 3 "$s" 2>/dev/null | tr -d '[:space:]')" && break
    done
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo "$ip" || echo ""
}

gen_path() { echo "/$(openssl rand -hex 8)"; }

write_vars() {
cat > "$VARS_FILE" << EOF
# Сгенерировано init.sh $(date '+%Y-%m-%d %H:%M:%S')

# --- UUID (make keys VAR=variant-c) ---
UUID_VLESS=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
UUID_VMESS=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy

# --- Домен и IP ---
DOMAIN=${1}
SERVER_IP=${2}

# --- TLS сертификат ---
# certbot certonly --standalone -d ${1}
CERT_FILE=/etc/letsencrypt/live/${1}/fullchain.pem
KEY_FILE=/etc/letsencrypt/live/${1}/privkey.pem

# --- Пути ---
VLESS_WS_PATH=${3}
VMESS_WS_PATH=${4}

# --- Внутренние порты sub-inbounds ---
VLESS_WS_PORT=${5}
VMESS_WS_PORT=${6}

# --- Nginx unix socket (decoy сайт) ---
H1_SOCK=/dev/shm/xraylab-c-h1.sock

# --- Subscription ---
SUB_PATH=/sub

# --- Клиент ---
SOCKS_PORT=${7}
HTTP_PORT=${8}
EOF
}

main() {
    echo > /dev/tty
    bold "  xray-lab · variant-c · Xray native fallbacks (All-in-One)"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" > /dev/tty
    echo > /dev/tty
    info "Архитектура: Xray :443 + TLS → fallbacks → WS inbounds + Nginx (unix socket)"
    warn "Reality в этой схеме НЕДОСТУПНА — fallbacks и Reality несовместимы."
    warn "Требуется TLS-сертификат для домена."
    echo > /dev/tty

    if (( AUTO )); then
        info "Режим --auto: дефолтные значения"
        [[ -f "$VARS_FILE" ]] && warn "vars.env уже существует — перезапись"
        SERVER_IP="$(detect_ip)"; [[ -n "$SERVER_IP" ]] || { echo "[✗] Нет SERVER_IP" > /dev/tty; exit 1; }
        ok "SERVER_IP: ${SERVER_IP}"
        write_vars "your-domain.com" "$SERVER_IP" \
            "$(gen_path)" "$(gen_path)" \
            "9001" "9002" "1080" "8118"
    else
        [[ -f "$VARS_FILE" ]] && {
            warn "vars.env уже существует"
            printf "  Продолжить? [y/N]: " > /dev/tty
            read -r c < /dev/tty; [[ "${c,,}" == "y" ]] || exit 0
        }

        echo > /dev/tty
        SERVER_IP="$(detect_ip)"
        [[ -n "$SERVER_IP" ]] && ok "Обнаружен IP: $SERVER_IP" || warn "IP не определён"
        SERVER_IP="$(ask "SERVER_IP" "$SERVER_IP")"
        [[ -n "$SERVER_IP" ]] || { echo "[✗] SERVER_IP обязателен" > /dev/tty; exit 1; }

        echo > /dev/tty
        info "Собственный домен с TLS-сертификатом (обязателен для Variant C)."
        DOMAIN="$(ask "DOMAIN" "your-domain.com")"

        echo > /dev/tty
        bold "  Пути для протоколов (Enter = автогенерация):"
        VLESS_WS_PATH="$(ask "VLESS_WS_PATH" "$(gen_path)")"
        VMESS_WS_PATH="$(ask "VMESS_WS_PATH" "$(gen_path)")"

        echo > /dev/tty
        bold "  Порты sub-inbounds и клиента:"
        VLESS_WS_PORT="$(ask "VLESS_WS_PORT" "9001")"
        VMESS_WS_PORT="$(ask "VMESS_WS_PORT" "9002")"
        SOCKS_PORT="$(ask   "SOCKS_PORT"     "1080")"
        HTTP_PORT="$(ask    "HTTP_PORT"       "8118")"
        echo > /dev/tty

        write_vars "$DOMAIN" "$SERVER_IP" \
            "$VLESS_WS_PATH" "$VMESS_WS_PATH" \
            "$VLESS_WS_PORT" "$VMESS_WS_PORT" \
            "$SOCKS_PORT" "$HTTP_PORT"
    fi

    ok "Записано: ${VARS_FILE}"
    echo > /dev/tty
    if (( ! AUTO )); then
        if [[ "${XRAY_QUICKSTART:-0}" == "1" ]]; then
            echo "  ↓ quickstart продолжает: keys → certbot → up → QR" > /dev/tty
        else
            bold "  Следующие шаги:"
            echo "    make keys VAR=variant-c           ← сгенерировать UUID_VLESS, UUID_VMESS" > /dev/tty
            echo "    certbot certonly -d \$DOMAIN       ← получить TLS сертификат" > /dev/tty
            echo "    make up VAR=variant-c              ← запустить стек" > /dev/tty
        fi
        echo > /dev/tty
    fi
}

main
