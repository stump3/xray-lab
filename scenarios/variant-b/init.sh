#!/usr/bin/env bash
# init.sh — инициализация vars.env для variant-b (Nginx stream SNI routing)
# Использование:
#   bash scenarios/variant-b/init.sh           — интерактивно
#   bash scenarios/variant-b/init.sh --auto    — без вопросов (все дефолты)
set -euo pipefail

AUTO=0
[[ "${1:-}" == "--auto" ]] && AUTO=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.env"

# ── Хелперы ───────────────────────────────────────────────────────────────────

bold()  { echo -e "\033[1m$*\033[0m" > /dev/tty; }
dim()   { echo -e "\033[2m$*\033[0m" > /dev/tty; }
ok()    { echo -e "  \033[32m[✓]\033[0m $*" > /dev/tty; }
info()  { echo -e "  \033[34m[·]\033[0m $*" > /dev/tty; }
warn()  { echo -e "  \033[33m[!]\033[0m $*" > /dev/tty; }

ask() {
    local label="$1" default="$2" value
    if [[ -n "$default" ]]; then
        printf "  %-32s [%s]: " "$label" "$default" > /dev/tty
    else
        printf "  %-32s : " "$label" > /dev/tty
    fi
    read -r value < /dev/tty
    echo "${value:-$default}"
}

detect_ip() {
    local ip=""
    for service in \
        "https://api.ipify.org" \
        "https://ifconfig.me" \
        "https://icanhazip.com" \
        "https://checkip.amazonaws.com"
    do
        ip="$(curl -fsSL --max-time 3 "$service" 2>/dev/null | tr -d '[:space:]')" && break
    done
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
       [[ "$ip" =~ ^[0-9a-fA-F:]+$ && "$ip" == *:* ]]; then
        echo "$ip"
    else
        echo ""
    fi
}

gen_path() { echo "/$(openssl rand -hex 8)"; }

write_vars() {
cat > "$VARS_FILE" << EOF
# Сгенерировано init.sh $(date '+%Y-%m-%d %H:%M:%S')
# vars.env добавлен в .gitignore — не коммить его

# --- Ключи Reality (генерируются через: make keys VAR=variant-b) ---
UUID_REALITY=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
UUID_WS=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
PRIV_KEY=your-private-key-base64
PUB_KEY=your-public-key-base64
SHORT_ID=aabbccdd11223344

# --- Домены ---
DOMAIN=${1}
REALITY_DOMAIN=${2}

# --- IP сервера ---
SERVER_IP=${3}

# --- Внутренние порты ---
REALITY_INBOUND_PORT=${4}
WS_INBOUND_PORT=${5}
NGINX_HTTPS_PORT=${6}

# --- WS путь ---
WS_PATH=${7}

# --- TLS сертификат ---
# Получить: certbot certonly --standalone -d ${1}
CERT_FILE=/etc/letsencrypt/live/${1}/fullchain.pem
KEY_FILE=/etc/letsencrypt/live/${1}/privkey.pem

# --- Subscription ---
SUB_PATH=/sub

# --- Клиент ---
SOCKS_PORT=${8}
HTTP_PORT=${9}
EOF
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    echo > /dev/tty
    bold "  xray-lab · variant-b · Nginx stream SNI routing"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" > /dev/tty
    echo > /dev/tty
    info "Архитектура: 443 → Nginx stream → Reality :REALITY_INBOUND_PORT / HTTPS :NGINX_HTTPS_PORT"
    info "Reality + WS+TLS на одном порту 443 без конфликтов."
    echo > /dev/tty

    if (( AUTO )); then
        info "Режим --auto: используются дефолтные значения"
        [[ -f "$VARS_FILE" ]] && warn "vars.env уже существует — перезапись"

        info "Определяем внешний IP сервера..."
        SERVER_IP="$(detect_ip)"
        [[ -n "$SERVER_IP" ]] || { echo "  [✗] Не удалось определить SERVER_IP" > /dev/tty; exit 1; }
        ok "SERVER_IP: ${SERVER_IP}"

        write_vars \
            "your-domain.com" "www.microsoft.com" "$SERVER_IP" \
            "8443" "9001" "7443" "$(gen_path)" "1080" "8118"
    else
        if [[ -f "$VARS_FILE" ]]; then
            warn "vars.env уже существует — значения будут перезаписаны"
            printf "  Продолжить? [y/N]: " > /dev/tty
            read -r confirm < /dev/tty
            [[ "${confirm,,}" == "y" ]] || { echo "  Отменено." > /dev/tty; exit 0; }
            echo > /dev/tty
        fi

        info "Определяем внешний IP сервера..."
        detected_ip="$(detect_ip)"
        [[ -n "$detected_ip" ]] && ok "Обнаружен: ${detected_ip}" || warn "Не удалось определить автоматически"
        SERVER_IP="$(ask "SERVER_IP" "$detected_ip")"
        [[ -n "$SERVER_IP" ]] || { echo "  [✗] SERVER_IP обязателен" > /dev/tty; exit 1; }

        echo > /dev/tty
        info "DOMAIN — твой собственный домен, чья A-запись указывает на этот сервер (${detected_ip:-SERVER_IP})."
        info "Нужен для Nginx HTTPS + WS+TLS части. Сертификат получишь через certbot после init."
        dim "  Пример: cdn.example.com, vpn.mysite.org"
        dim "  ⚠  Не вводи чужой домен (github.com, microsoft.com и т.п.) — сертификат не получить."
        DOMAIN="$(ask "DOMAIN" "your-domain.com")"

        echo > /dev/tty
        info "REALITY_DOMAIN — чужой публичный сайт-декой для Reality (не твой)."
        info "Требования: без Cloudflare, поддерживает TLS 1.3 + HTTP/2."
        dim "  Хорошие варианты: www.microsoft.com, www.apple.com, addons.mozilla.org"
        while true; do
            REALITY_DOMAIN="$(ask "REALITY_DOMAIN" "www.microsoft.com")"
            if [[ "$REALITY_DOMAIN" == "$DOMAIN" ]]; then
                warn "REALITY_DOMAIN не может совпадать с DOMAIN (${DOMAIN}) — это твой сервер."
                warn "Введи чужой сайт: www.microsoft.com, www.apple.com и т.п."
            else
                break
            fi
        done

        echo > /dev/tty
        bold "  Внутренние порты (Enter = оставить дефолт):"
        warn ":443 и :80 зарезервированы — введи любой другой порт."
        while true; do
            REALITY_INBOUND_PORT="$(ask "REALITY_INBOUND_PORT" "8443")"
            [[ "$REALITY_INBOUND_PORT" == "443" || "$REALITY_INBOUND_PORT" == "80" ]] \
                && warn "Нельзя использовать $REALITY_INBOUND_PORT — это публичный порт Nginx stream." \
                || break
        done
        while true; do
            WS_INBOUND_PORT="$(ask "WS_INBOUND_PORT" "9001")"
            [[ "$WS_INBOUND_PORT" == "443" || "$WS_INBOUND_PORT" == "80" ]] \
                && warn "Нельзя использовать $WS_INBOUND_PORT — это публичный порт Nginx stream." \
                || break
        done
        while true; do
            NGINX_HTTPS_PORT="$(ask "NGINX_HTTPS_PORT" "7443")"
            [[ "$NGINX_HTTPS_PORT" == "443" || "$NGINX_HTTPS_PORT" == "80" ]] \
                && warn "Нельзя использовать $NGINX_HTTPS_PORT — это публичный порт Nginx stream." \
                || break
        done

        echo > /dev/tty
        info "WS path — случайный URL-путь. Оставь пустым для автогенерации."
        WS_PATH="$(ask "WS_PATH" "$(gen_path)")"

        echo > /dev/tty
        bold "  Клиентские порты:"
        SOCKS_PORT="$(ask "SOCKS_PORT" "1080")"
        HTTP_PORT="$(ask  "HTTP_PORT"  "8118")"
        echo > /dev/tty

        write_vars \
            "$DOMAIN" "$REALITY_DOMAIN" "$SERVER_IP" \
            "$REALITY_INBOUND_PORT" "$WS_INBOUND_PORT" "$NGINX_HTTPS_PORT" \
            "$WS_PATH" "$SOCKS_PORT" "$HTTP_PORT"
    fi

    ok "Записано: ${VARS_FILE}"
    echo > /dev/tty
    if (( ! AUTO )); then
        bold "  Следующие шаги:"
        echo "    make keys VAR=variant-b         ← сгенерировать UUID, x25519, shortId" > /dev/tty
        echo "    certbot certonly -d \$DOMAIN    ← получить TLS сертификат" > /dev/tty
        echo "    make up VAR=variant-b            ← запустить стек" > /dev/tty
        echo > /dev/tty
    fi
}

main
