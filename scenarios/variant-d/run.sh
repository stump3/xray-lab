#!/usr/bin/env bash
# run.sh — управление стеком variant-d (Self-SNI: VLESS+TLS+Vision + Nginx decoy)
# Использование:
#   ./run.sh up         — поднять Nginx (HTTP redirect + decoy) + Xray (:443)
#   ./run.sh down       — остановить всё
#   ./run.sh restart    — перезапустить
#   ./run.sh logs       — хвост логов Xray
#   ./run.sh status     — статус процессов
#   ./run.sh client     — поднять клиентский Xray (VLESS+TCP+TLS+Vision, SOCKS5)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.env"
TMP_DIR="/tmp/xray-lab-variant-d"

# ── Загрузка переменных ────────────────────────────────────────────────────────

load_vars() {
    [[ -f "$VARS_FILE" ]] || {
        echo "ERROR: vars.env не найден — запусти: make init VAR=variant-d"
        exit 1
    }
    set -a; source "$VARS_FILE"; set +a
    export DOLLAR='$'
    export NGINX_PID="${TMP_DIR}/nginx.pid"
}

# ── Рендер шаблонов ────────────────────────────────────────────────────────────

render_json() {
    local tpl="$1" out="$2"
    envsubst < "$tpl" > "$out"
    echo "  rendered: $(basename "$tpl") → $out"
}

render_nginx() {
    local tpl="$1" out="$2"
    envsubst '${DOMAIN}${NGINX_DECOY_PORT}${DOLLAR}${NGINX_PID}' \
        < "$tpl" > "$out"
    echo "  rendered: $(basename "$tpl") → $out"
}

# ── Проверки предусловий ───────────────────────────────────────────────────────

check_prereqs() {
    if [[ ! -f "${CERT_FILE:-}" ]]; then
        echo "  [✗] TLS-сертификат не найден: ${CERT_FILE:-не задан}"
        echo "      Variant D требует сертификат. Получить:"
        echo "      certbot certonly --standalone -d ${DOMAIN:-your-domain.com}"
        exit 1
    fi
}

# ── Команды ───────────────────────────────────────────────────────────────────

cmd_up() {
    load_vars
    mkdir -p "$TMP_DIR"
    check_prereqs

    echo "==> Рендер конфигов..."
    render_json  "${SCRIPT_DIR}/xray-server.json.tpl" "${TMP_DIR}/xray-server.json"
    render_nginx "${SCRIPT_DIR}/nginx.conf.tpl"       "${TMP_DIR}/nginx.conf"

    mkdir -p /var/log/xray

    echo "==> Валидация xray-server.json..."
    xray run -test -c "${TMP_DIR}/xray-server.json" \
        && echo "    [OK] конфиг валиден" \
        || { echo "    [FAIL] невалидный конфиг"; exit 1; }

    # Nginx стартует первым: Xray fallback будет писать на :NGINX_DECOY_PORT сразу
    echo "==> Запуск Nginx (HTTP :80 redirect + decoy 127.0.0.1:${NGINX_DECOY_PORT})..."
    sudo nginx -t -c "${TMP_DIR}/nginx.conf" \
        && sudo nginx -c "${TMP_DIR}/nginx.conf" \
        && echo "    [OK] Nginx запущен" \
        || { echo "    [FAIL] Nginx не стартовал"; exit 1; }

    # Проверяем что decoy порт доступен перед запуском Xray
    local retries=0
    while ! ss -tlnp "sport = :${NGINX_DECOY_PORT}" 2>/dev/null | grep -q "127.0.0.1" \
          && (( retries < 10 )); do
        sleep 0.5; (( retries++ ))
    done

    echo "==> Запуск Xray (:443, VLESS+TLS+Vision, fallback → :${NGINX_DECOY_PORT})..."
    sudo xray run -c "${TMP_DIR}/xray-server.json" &> "${TMP_DIR}/xray.log" &
    echo $! > "${TMP_DIR}/xray.pid"
    sleep 1

    if kill -0 "$(cat "${TMP_DIR}/xray.pid")" 2>/dev/null; then
        echo "    [OK] Xray запущен (pid $(cat "${TMP_DIR}/xray.pid"))"
    else
        echo "    [FAIL] Xray упал, смотри логи:"
        tail -20 "${TMP_DIR}/xray.log"
        exit 1
    fi

    echo
    echo "  Xray:   0.0.0.0:443  (VLESS+TLS+Vision)"
    echo "  Decoy:  127.0.0.1:${NGINX_DECOY_PORT}  (Nginx, только loopback)"
    echo "  HTTP:   0.0.0.0:80  → 301 HTTPS"
    echo "  Domain: ${DOMAIN}"
    echo "  Stats:  127.0.0.1:10085"
}

cmd_down() {
    echo "==> Остановка..."
    if [[ -f "${TMP_DIR}/xray.pid" ]]; then
        sudo kill "$(cat "${TMP_DIR}/xray.pid")" 2>/dev/null \
            && echo "    [OK] Xray остановлен"
        rm -f "${TMP_DIR}/xray.pid"
    fi
    local npid="${TMP_DIR}/nginx.pid"
    if [[ -f "$npid" ]]; then
        sudo kill "$(cat "$npid")" 2>/dev/null \
            && echo "    [OK] Nginx остановлен"
    else
        sudo nginx -s stop 2>/dev/null && echo "    [OK] Nginx остановлен" || true
    fi
}

cmd_client() {
    load_vars
    mkdir -p "$TMP_DIR"
    echo "==> Запуск клиентского Xray (VLESS+TCP+TLS+Vision, SOCKS5 :${SOCKS_PORT})..."
    envsubst < "${SCRIPT_DIR}/xray-client.json.tpl" > "${TMP_DIR}/xray-client.json"
    xray run -c "${TMP_DIR}/xray-client.json"
}

cmd_logs() {
    tail -f "${TMP_DIR}/xray.log" 2>/dev/null \
        || echo "Логи не найдены — сначала ./run.sh up"
}

cmd_status() {
    echo "==> Xray (:443):"
    if [[ -f "${TMP_DIR}/xray.pid" ]] && kill -0 "$(cat "${TMP_DIR}/xray.pid")" 2>/dev/null; then
        echo "    запущен (pid $(cat "${TMP_DIR}/xray.pid"))"
    else
        echo "    не запущен"
    fi
    echo "==> Ports:"
    ss -tlnp | grep -E ':443 |:80 |:8080|:10085' || echo "    ничего не слушает"
}

case "${1:-}" in
    up)      cmd_up      ;;
    down)    cmd_down    ;;
    restart) cmd_down; cmd_up ;;
    logs)    cmd_logs    ;;
    status)  cmd_status  ;;
    client)  cmd_client  ;;
    *)
        echo "Использование: $0 {up|down|restart|logs|status|client}"
        exit 1
        ;;
esac
