#!/usr/bin/env bash
# init.sh — инициализация vars.env для variant-b2
# (Nginx stream SNI routing + Hysteria2 на :443 UDP)
# Использование:
#   bash scenarios/variant-b2/init.sh           — интерактивно
#   bash scenarios/variant-b2/init.sh --auto    — без вопросов (все дефолты)
set -euo pipefail

AUTO=0
[[ "${1:-}" == "--auto" ]] && AUTO=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.env"

bold()  { echo -e "\033[1m$*\033[0m" > /dev/tty; }
dim()   { echo -e "\033[2m$*\033[0m" > /dev/tty; }
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
    for s in "https://api.ipify.org" "https://ifconfig.me" \
             "https://icanhazip.com" "https://checkip.amazonaws.com"; do
        ip="$(curl -fsSL --max-time 3 "$s" 2>/dev/null | tr -d '[:space:]')" && break
    done
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo "$ip" || echo ""
}

gen_path() { echo "/$(openssl rand -hex 8)"; }

write_vars() {
    local domain="$1" reality_domain="$2" server_ip="$3"
    local reality_port="$4" ws_port="$5" nginx_https_port="$6"
    local ws_path="$7" socks_port="$8" http_port="$9"
    local h2_domain="${10}" h2_same_cert="${11}"

    # Пути к сертификату Hysteria2
    local h2_cert h2_key
    if [[ "$h2_same_cert" == "1" ]]; then
        h2_cert="/etc/letsencrypt/live/${domain}/fullchain.pem"
        h2_key="/etc/letsencrypt/live/${domain}/privkey.pem"
    else
        h2_cert="/etc/letsencrypt/live/${h2_domain}/fullchain.pem"
        h2_key="/etc/letsencrypt/live/${h2_domain}/privkey.pem"
    fi

cat > "$VARS_FILE" << EOF
# Сгенерировано init.sh $(date '+%Y-%m-%d %H:%M:%S')

# --- Ключи (make keys VAR=variant-b2) ---
UUID_REALITY=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
UUID_WS=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
PRIV_KEY=your-private-key-base64
PUB_KEY=your-public-key-base64
SHORT_ID=aabbccdd11223344
H2_PASSWORD=your-hysteria2-password

# --- Домены ---
DOMAIN=${domain}
REALITY_DOMAIN=${reality_domain}

# --- Hysteria2 домен и сертификат ---
H2_DOMAIN=${h2_domain}
H2_CERT_FILE=${h2_cert}
H2_KEY_FILE=${h2_key}

# --- IP сервера ---
SERVER_IP=${server_ip}

# --- Внутренние порты ---
REALITY_INBOUND_PORT=${reality_port}
WS_INBOUND_PORT=${ws_port}
NGINX_HTTPS_PORT=${nginx_https_port}

# --- WS путь ---
WS_PATH=${ws_path}

# --- TLS сертификат (Nginx HTTPS + WS) ---
# Получить: certbot certonly --standalone -d ${domain}
CERT_FILE=/etc/letsencrypt/live/${domain}/fullchain.pem
KEY_FILE=/etc/letsencrypt/live/${domain}/privkey.pem

# --- Subscription ---
SUB_PATH=/sub

# --- Клиент ---
SOCKS_PORT=${socks_port}
HTTP_PORT=${http_port}
EOF
}

ask_h2_domain() {
    # Вопрос: свой домен или отдельный для Hysteria2
    local main_domain="$1"
    echo > /dev/tty
    bold "  Hysteria2: TLS-сертификат"
    echo "  ──────────────────────────────────────────" > /dev/tty
    info "Hysteria2 требует TLS. Можно использовать тот же домен"
    info "что и для Nginx HTTPS (${main_domain}), или отдельный."
    echo > /dev/tty
    echo "    1) Использовать тот же домен (${main_domain})" > /dev/tty
    echo "    2) Указать отдельный домен (получить новый сертификат)" > /dev/tty
    echo > /dev/tty

    local choice
    while true; do
        printf "  Выбор [1/2]: " > /dev/tty
        read -r choice < /dev/tty
        case "$choice" in
            1) echo "same" ; return ;;
            2) echo "separate" ; return ;;
            *) warn "Введи 1 или 2" ;;
        esac
    done
}

main() {
    echo > /dev/tty
    bold "  xray-lab · variant-b2 · Nginx stream SNI + Hysteria2"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" > /dev/tty
    echo > /dev/tty
    info "Архитектура: TCP:443 → Nginx stream SNI → Reality / HTTPS+WS"
    info "             UDP:443 → Xray Hysteria2 (не конфликтует с Nginx)"
    echo > /dev/tty

    if (( AUTO )); then
        info "Режим --auto: дефолтные значения"
        [[ -f "$VARS_FILE" ]] && warn "vars.env уже существует — перезапись"
        SERVER_IP="$(detect_ip)"
        [[ -n "$SERVER_IP" ]] || { echo "[✗] Нет SERVER_IP" > /dev/tty; exit 1; }
        ok "SERVER_IP: ${SERVER_IP}"
        write_vars \
            "your-domain.com" "www.microsoft.com" "$SERVER_IP" \
            "8443" "9001" "7443" "$(gen_path)" "1080" "8118" \
            "your-domain.com" "1"
        ok "Записано: ${VARS_FILE}"
        return
    fi

    # ── Интерактивный режим ────────────────────────────────────────────────────

    [[ -f "$VARS_FILE" ]] && {
        warn "vars.env уже существует"
        printf "  Продолжить? [y/N]: " > /dev/tty
        read -r c < /dev/tty; [[ "${c,,}" == "y" ]] || exit 0
        echo > /dev/tty
    }

    # SERVER_IP
    info "Определяем внешний IP сервера..."
    detected_ip="$(detect_ip)"
    [[ -n "$detected_ip" ]] && ok "Обнаружен: ${detected_ip}" || warn "Не удалось определить автоматически"
    SERVER_IP="$(ask "SERVER_IP" "$detected_ip")"
    [[ -n "$SERVER_IP" ]] || { echo "[✗] SERVER_IP обязателен" > /dev/tty; exit 1; }

    # DOMAIN
    echo > /dev/tty
    info "DOMAIN — твой собственный домен (A-запись → ${SERVER_IP})."
    info "Нужен для Nginx HTTPS + WS+TLS части."
    dim "  ⚠  Не вводи чужой домен — сертификат не получить."
    DOMAIN="$(ask "DOMAIN" "your-domain.com")"

    # REALITY_DOMAIN
    echo > /dev/tty
    info "REALITY_DOMAIN — чужой публичный сайт-декой для Reality."
    info "Требования: без Cloudflare, TLS 1.3 + HTTP/2."
    dim "  Хорошие варианты: www.microsoft.com, www.apple.com"
    while true; do
        REALITY_DOMAIN="$(ask "REALITY_DOMAIN" "www.microsoft.com")"
        [[ "$REALITY_DOMAIN" != "$DOMAIN" ]] && break
        warn "REALITY_DOMAIN не может совпадать с DOMAIN — введи чужой сайт."
    done

    # Hysteria2 домен
    H2_CHOICE="$(ask_h2_domain "$DOMAIN")"
    if [[ "$H2_CHOICE" == "same" ]]; then
        H2_DOMAIN="$DOMAIN"
        H2_SAME_CERT="1"
        ok "Hysteria2 будет использовать сертификат ${DOMAIN}"
    else
        echo > /dev/tty
        info "Введи отдельный домен для Hysteria2 (A-запись тоже должна → ${SERVER_IP})."
        H2_DOMAIN="$(ask "H2_DOMAIN" "h2.${DOMAIN}")"
        H2_SAME_CERT="0"
        ok "Hysteria2 домен: ${H2_DOMAIN} (сертификат получим отдельно)"
    fi

    # Внутренние порты
    echo > /dev/tty
    bold "  Внутренние порты (Enter = дефолт):"
    warn ":443 и :80 зарезервированы — введи любой другой."
    while true; do
        REALITY_INBOUND_PORT="$(ask "REALITY_INBOUND_PORT" "8443")"
        [[ "$REALITY_INBOUND_PORT" == "443" || "$REALITY_INBOUND_PORT" == "80" ]] \
            && warn "Нельзя использовать $REALITY_INBOUND_PORT" || break
    done
    while true; do
        WS_INBOUND_PORT="$(ask "WS_INBOUND_PORT" "9001")"
        [[ "$WS_INBOUND_PORT" == "443" || "$WS_INBOUND_PORT" == "80" ]] \
            && warn "Нельзя использовать $WS_INBOUND_PORT" || break
    done
    while true; do
        NGINX_HTTPS_PORT="$(ask "NGINX_HTTPS_PORT" "7443")"
        [[ "$NGINX_HTTPS_PORT" == "443" || "$NGINX_HTTPS_PORT" == "80" ]] \
            && warn "Нельзя использовать $NGINX_HTTPS_PORT" || break
    done

    # WS путь
    echo > /dev/tty
    WS_PATH="$(ask "WS_PATH" "$(gen_path)")"

    # Клиентские порты
    echo > /dev/tty
    bold "  Клиентские порты:"
    SOCKS_PORT="$(ask "SOCKS_PORT" "1080")"
    HTTP_PORT="$(ask  "HTTP_PORT"  "8118")"
    echo > /dev/tty

    write_vars \
        "$DOMAIN" "$REALITY_DOMAIN" "$SERVER_IP" \
        "$REALITY_INBOUND_PORT" "$WS_INBOUND_PORT" "$NGINX_HTTPS_PORT" \
        "$WS_PATH" "$SOCKS_PORT" "$HTTP_PORT" \
        "$H2_DOMAIN" "$H2_SAME_CERT"

    ok "Записано: ${VARS_FILE}"
    echo > /dev/tty

    if [[ "${XRAY_QUICKSTART:-0}" == "1" ]]; then
        echo "  ↓ quickstart продолжает: keys → certbot → up → QR" > /dev/tty
    else
        bold "  Следующие шаги:"
        echo "    make keys VAR=variant-b2       ← UUID, x25519, H2_PASSWORD" > /dev/tty
        echo "    certbot certonly -d $DOMAIN    ← сертификат для Nginx+WS" > /dev/tty
        if [[ "$H2_SAME_CERT" == "0" ]]; then
            echo "    certbot certonly -d $H2_DOMAIN ← отдельный серт для Hysteria2" > /dev/tty
        fi
        echo "    make up VAR=variant-b2          ← запустить стек" > /dev/tty
        echo "    make link-qr VAR=variant-b2     ← 3 ссылки: Reality + WS + H2" > /dev/tty
    fi
    echo > /dev/tty
}

main
