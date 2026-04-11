#!/usr/bin/env bash
# maybe-certbot.sh — предлагает получить TLS-сертификат если вариант его требует
# Использование: bash tools/maybe-certbot.sh <variant>
# Вызывается из quickstart между keys и up.
set -euo pipefail

VARIANT="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; GRAY=$'\033[90m'

ok()   { printf "  ${GREEN}[✓]${RESET} %s\n" "$*" > /dev/tty; }
info() { printf "  ${CYAN}[·]${RESET} %s\n" "$*" > /dev/tty; }
warn() { printf "  ${YELLOW}[!]${RESET} %s\n" "$*" > /dev/tty; }
dim()  { printf "  ${DIM}${GRAY}%s${RESET}\n" "$*" > /dev/tty; }

# Варианты которым не нужен сертификат
case "$VARIANT" in
    variant-a)
        info "variant-a использует Reality — TLS-сертификат не нужен."
        exit 0
        ;;
esac

# Загружаем vars.env выбранного варианта
VARS="${REPO_ROOT}/scenarios/${VARIANT}/vars.env"
[[ -f "$VARS" ]] || { warn "vars.env не найден — пропускаю certbot"; exit 0; }
set -a; source "$VARS"; set +a

DOMAIN="${DOMAIN:-}"
CERT_FILE="${CERT_FILE:-}"

[[ -n "$DOMAIN" && "$DOMAIN" != "your-domain.com" ]] || {
    warn "DOMAIN не задан или не изменён — пропускаю получение сертификата."
    warn "После настройки домена запусти: certbot certonly --standalone -d \$DOMAIN"
    exit 0
}

# Сертификат уже есть
if [[ -f "$CERT_FILE" ]]; then
    ok "Сертификат уже существует: $CERT_FILE"
    exit 0
fi

printf '\n' > /dev/tty
printf "  ${BOLD}Получение TLS-сертификата для ${DOMAIN}${RESET}\n" > /dev/tty
printf "  ──────────────────────────────────────────────\n" > /dev/tty
info "Для WS+TLS части нужен сертификат Let's Encrypt."
info "Домен: ${BOLD}${DOMAIN}${RESET}"
printf '\n' > /dev/tty
warn "Убедись что A-запись ${DOMAIN} → ${SERVER_IP:-<SERVER_IP>} уже активна"
warn "и порт :80 свободен (certbot standalone использует его для проверки)."
printf '\n' > /dev/tty
printf "  Получить сертификат сейчас? [y/N]: " > /dev/tty
read -r answer < /dev/tty

if [[ "${answer,,}" != "y" ]]; then
    printf '\n' > /dev/tty
    warn "Сертификат не получен. WS+TLS часть не запустится."
    dim "Получить позже: certbot certonly --standalone -d ${DOMAIN}"
    dim "Затем: make up VAR=${VARIANT}"
    printf '\n' > /dev/tty
    exit 0
fi

printf '\n' > /dev/tty
info "Запускаем certbot..."
if ! command -v certbot &>/dev/null; then
    warn "certbot не установлен. Установить?"
    printf "  apt install certbot? [y/N]: " > /dev/tty
    read -r install_answer < /dev/tty
    if [[ "${install_answer,,}" == "y" ]]; then
        apt-get install -y certbot > /dev/tty 2>&1
    else
        warn "Установи certbot вручную: apt install certbot"
        exit 0
    fi
fi

# Запускаем certbot standalone
if certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos \
    --email "admin@${DOMAIN}" 2>&1 | tee /dev/tty; then
    printf '\n' > /dev/tty
    ok "Сертификат получен: /etc/letsencrypt/live/${DOMAIN}/"
else
    printf '\n' > /dev/tty
    warn "certbot завершился с ошибкой."
    dim "Проверь что A-запись ${DOMAIN} → ${SERVER_IP:-?} активна и :80 свободен."
    dim "Попробуй вручную: certbot certonly --standalone -d ${DOMAIN}"
    exit 0  # не exit 1 — пусть quickstart продолжится, run.sh сам скажет если нет серта
fi
