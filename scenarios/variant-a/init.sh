#!/usr/bin/env bash
# init.sh — инициализация vars.env для variant-a
# Использование:
#   bash scenarios/variant-a/init.sh           — интерактивно
#   bash scenarios/variant-a/init.sh --auto    — без вопросов (все дефолты)
#   make init                                  — интерактивно
#   make init-auto                             — без вопросов
set -euo pipefail

AUTO=0
[[ "${1:-}" == "--auto" ]] && AUTO=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.env"
EXAMPLE_FILE="${SCRIPT_DIR}/vars.env.example"

# ── Хелперы ───────────────────────────────────────────────────────────────────

bold()  { echo -e "\033[1m$*\033[0m" > /dev/tty; }
dim()   { echo -e "\033[2m$*\033[0m" > /dev/tty; }
ok()    { echo -e "  \033[32m[✓]\033[0m $*" > /dev/tty; }
info()  { echo -e "  \033[34m[·]\033[0m $*" > /dev/tty; }
warn()  { echo -e "  \033[33m[!]\033[0m $*" > /dev/tty; }

# Спросить значение; $1 — подпись, $2 — дефолт
ask() {
    local label="$1" default="$2" value
    if [[ -n "$default" ]]; then
        printf "  %-28s [%s]: " "$label" "$default" > /dev/tty
    else
        printf "  %-28s : " "$label" > /dev/tty
    fi
    read -r value < /dev/tty
    echo "${value:-$default}"
}

# ── Автоопределение SERVER_IP ─────────────────────────────────────────────────

detect_ip() {
    local ip=""

    # Пробуем несколько источников по порядку
    for service in \
        "https://api.ipify.org" \
        "https://ifconfig.me" \
        "https://icanhazip.com" \
        "https://checkip.amazonaws.com"
    do
        ip="$(curl -fsSL --max-time 3 "$service" 2>/dev/null | tr -d '[:space:]')" && break
    done

    # Базовая проверка формата IPv4 или IPv6
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
       [[ "$ip" =~ ^[0-9a-fA-F:]+$ && "$ip" == *:* ]]; then
        echo "$ip"
    else
        echo ""
    fi
}

# ── Генерация случайного XHTTP_PATH ──────────────────────────────────────────

gen_path() {
    # 16 случайных hex-символов → /xxxxxxxxxxxxxxxx
    echo "/$(openssl rand -hex 8)"
}

# ── Запись vars.env ───────────────────────────────────────────────────────────

write_vars() {
    local server_ip="$1" reality_domain="$2" xray_port="$3"
    local xhttp_path="$4" socks_port="$5" http_port="$6"
    local nginx_port="$7" sub_path="$8"

    cat > "$VARS_FILE" << EOF
# Сгенерировано init.sh $(date '+%Y-%m-%d %H:%M:%S')
# vars.env добавлен в .gitignore — не коммить его

# --- Генерируется через: make keys ---
UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
PRIV_KEY=your-private-key-base64
PUB_KEY=your-public-key-base64
SHORT_ID=aabbccdd11223344

# --- Reality decoy domain ---
# Требования: без Cloudflare, TLS 1.3 + HTTP/2
# Проверка: make check-domain D=${reality_domain}
REALITY_DOMAIN=${reality_domain}

# --- Сетевые параметры ---
SERVER_IP=${server_ip}
XRAY_PORT=${xray_port}
XHTTP_PATH=${xhttp_path}

# --- Клиент (SOCKS5 прокси, который поднимет client.json) ---
SOCKS_PORT=${socks_port}
HTTP_PORT=${http_port}

# --- Nginx для subscription endpoint (опционально) ---
NGINX_PORT=${nginx_port}
SUB_PATH=${sub_path}
EOF
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    echo > /dev/tty
    bold "  xray-lab · variant-a · инициализация"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" > /dev/tty

    if (( AUTO )); then
        # ── Автоматический режим: никаких вопросов ────────────────────────────
        info "Режим --auto: используются дефолтные значения"

        # vars.env уже существует — перезаписываем без вопросов
        [[ -f "$VARS_FILE" ]] && warn "vars.env уже существует — перезапись"

        info "Определяем внешний IP сервера..."
        SERVER_IP="$(detect_ip)"
        [[ -n "$SERVER_IP" ]] || { echo "  [✗] Не удалось определить SERVER_IP; укажи вручную через make init" > /dev/tty; exit 1; }
        ok "SERVER_IP: ${SERVER_IP}"

        REALITY_DOMAIN="www.microsoft.com"
        XHTTP_PATH="$(gen_path)"
        XRAY_PORT="443"
        SOCKS_PORT="1080"
        HTTP_PORT="8118"
        NGINX_PORT="8080"
        SUB_PATH="/sub"

        ok "REALITY_DOMAIN: ${REALITY_DOMAIN}"
        ok "XHTTP_PATH:     ${XHTTP_PATH}"
        ok "XRAY_PORT:      ${XRAY_PORT}"
    else
        # ── Интерактивный режим ───────────────────────────────────────────────

        # Предупреждение если vars.env уже есть
        if [[ -f "$VARS_FILE" ]]; then
            warn "vars.env уже существует — значения будут перезаписаны"
            printf "  Продолжить? [y/N]: " > /dev/tty
            read -r confirm < /dev/tty
            [[ "${confirm,,}" == "y" ]] || { echo "  Отменено." > /dev/tty; exit 0; }
            echo > /dev/tty
        fi

        # SERVER_IP
        echo > /dev/tty
        info "Определяем внешний IP сервера..."
        detected_ip="$(detect_ip)"
        if [[ -n "$detected_ip" ]]; then
            ok "Обнаружен: ${detected_ip}"
        else
            warn "Не удалось определить автоматически"
        fi
        SERVER_IP="$(ask "SERVER_IP" "$detected_ip")"
        [[ -n "$SERVER_IP" ]] || { echo "  [✗] SERVER_IP обязателен" > /dev/tty; exit 1; }

        # REALITY_DOMAIN
        echo > /dev/tty
        info "Reality decoy-домен — публичный сайт без Cloudflare, TLS 1.3 + HTTP/2."
        dim "  Хорошие варианты: www.microsoft.com, www.apple.com, addons.mozilla.org"
        REALITY_DOMAIN="$(ask "REALITY_DOMAIN" "www.microsoft.com")"

        # XHTTP_PATH
        echo > /dev/tty
        generated_path="$(gen_path)"
        info "XHTTP path — случайный URL-путь. Оставь пустым для автогенерации."
        XHTTP_PATH="$(ask "XHTTP_PATH" "$generated_path")"

        # Порты
        echo > /dev/tty
        bold "  Порты (Enter = оставить дефолт):"
        XRAY_PORT="$(ask   "XRAY_PORT (сервер)"     "443")"
        SOCKS_PORT="$(ask  "SOCKS_PORT (клиент)"    "1080")"
        HTTP_PORT="$(ask   "HTTP_PORT (клиент)"     "8118")"
        NGINX_PORT="$(ask  "NGINX_PORT (sub)"       "8080")"
        SUB_PATH="$(ask    "SUB_PATH"               "/sub")"
        echo > /dev/tty
    fi

    write_vars \
        "$SERVER_IP" "$REALITY_DOMAIN" "$XRAY_PORT" \
        "$XHTTP_PATH" "$SOCKS_PORT" "$HTTP_PORT" \
        "$NGINX_PORT" "$SUB_PATH"

    ok "Записано: ${VARS_FILE}"
    echo > /dev/tty
    if (( ! AUTO )); then
        if [[ "${XRAY_QUICKSTART:-0}" == "1" ]]; then
            echo "  ↓ quickstart продолжает: keys → up → QR" > /dev/tty
        else
            bold "  Следующий шаг:"
            echo "    make keys   ← сгенерировать UUID, x25519 ключи, shortId" > /dev/tty
        fi
        echo > /dev/tty
    fi
}

main
