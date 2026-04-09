#!/usr/bin/env bash
# init.sh — инициализация vars.env для variant-d (Self-SNI)
# Использование:
#   bash scenarios/variant-d/init.sh           — интерактивно
#   bash scenarios/variant-d/init.sh --auto    — без вопросов (все дефолты)
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
    [[ -n "$default" ]] \
        && printf "  %-32s [%s]: " "$label" "$default" > /dev/tty \
        || printf "  %-32s : " "$label" > /dev/tty
    read -r value < /dev/tty
    echo "${value:-$default}"
}

detect_ip() {
    local ip=""
    for s in \
        "https://api.ipify.org" \
        "https://ifconfig.me" \
        "https://icanhazip.com" \
        "https://checkip.amazonaws.com"
    do
        ip="$(curl -fsSL --max-time 3 "$s" 2>/dev/null | tr -d '[:space:]')" && break
    done
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
       [[ "$ip" =~ ^[0-9a-fA-F:]+$ && "$ip" == *:* ]]; then
        echo "$ip"
    else
        echo ""
    fi
}

write_vars() {
    local domain="$1" server_ip="$2" decoy_port="$3" socks="$4" http="$5"
cat > "$VARS_FILE" << EOF
# Сгенерировано init.sh $(date '+%Y-%m-%d %H:%M:%S')
# vars.env добавлен в .gitignore — не коммить его

# --- UUID (make keys VAR=variant-d) ---
UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# --- Домен ---
DOMAIN=${domain}

# --- IP сервера ---
SERVER_IP=${server_ip}

# --- TLS сертификат (Xray терминирует напрямую) ---
# certbot certonly --standalone -d ${domain}
CERT_FILE=/etc/letsencrypt/live/${domain}/fullchain.pem
KEY_FILE=/etc/letsencrypt/live/${domain}/privkey.pem

# --- Nginx decoy порт (только 127.0.0.1, произвольный выбор) ---
NGINX_DECOY_PORT=${decoy_port}

# --- Клиент ---
SOCKS_PORT=${socks}
HTTP_PORT=${http}
EOF
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    echo > /dev/tty
    bold "  xray-lab · variant-d · Self-SNI (VLESS+TLS, собственный decoy)"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" > /dev/tty
    echo > /dev/tty
    info "Архитектура: Xray :443 (VLESS+TLS+Vision) → fallback → Nginx :DECOY (decoy сайт)"
    info "Домен, сертификат, IP и сайт полностью согласованы — максимальная достоверность."
    warn "Reality в этой схеме НЕДОСТУПНА. CDN несовместим с xtls-rprx-vision."
    echo > /dev/tty

    if (( AUTO )); then
        info "Режим --auto: дефолтные значения"
        [[ -f "$VARS_FILE" ]] && warn "vars.env уже существует — перезапись"

        info "Определяем внешний IP сервера..."
        SERVER_IP="$(detect_ip)"
        [[ -n "$SERVER_IP" ]] || { echo "  [✗] Не удалось определить SERVER_IP" > /dev/tty; exit 1; }
        ok "SERVER_IP: ${SERVER_IP}"

        write_vars "your-domain.com" "$SERVER_IP" "8080" "1080" "8118"
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
        [[ -n "$detected_ip" ]] && ok "Обнаружен: ${detected_ip}" || warn "IP не определён"
        SERVER_IP="$(ask "SERVER_IP" "$detected_ip")"
        [[ -n "$SERVER_IP" ]] || { echo "  [✗] SERVER_IP обязателен" > /dev/tty; exit 1; }

        echo > /dev/tty
        info "Собственный домен (обязателен — нужен TLS-сертификат и DNS A-запись → SERVER_IP)."
        DOMAIN="$(ask "DOMAIN" "your-domain.com")"

        echo > /dev/tty
        info "Nginx decoy порт — слушает только на 127.0.0.1, снаружи не виден."
        dim "  Xray fallback пишет сюда нераспознанный трафик."
        NGINX_DECOY_PORT="$(ask "NGINX_DECOY_PORT" "8080")"

        echo > /dev/tty
        bold "  Клиентские порты:"
        SOCKS_PORT="$(ask "SOCKS_PORT" "1080")"
        HTTP_PORT="$(ask  "HTTP_PORT"  "8118")"
        echo > /dev/tty

        write_vars "$DOMAIN" "$SERVER_IP" "$NGINX_DECOY_PORT" "$SOCKS_PORT" "$HTTP_PORT"
    fi

    ok "Записано: ${VARS_FILE}"
    echo > /dev/tty
    if (( ! AUTO )); then
        bold "  Следующие шаги:"
        echo "    make keys VAR=variant-d           ← сгенерировать UUID" > /dev/tty
        echo "    certbot certonly -d \$DOMAIN       ← получить TLS сертификат" > /dev/tty
        echo "    make up VAR=variant-d              ← запустить стек" > /dev/tty
        echo > /dev/tty
    fi
}

main
