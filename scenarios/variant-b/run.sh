#!/usr/bin/env bash
# run.sh — управление стеком variant-b (Nginx stream SNI routing)
# Использование:
#   ./run.sh up         — поднять Nginx (stream) + Xray (два inbound)
#   ./run.sh down       — остановить всё
#   ./run.sh restart    — перезапустить
#   ./run.sh logs       — хвост логов Xray
#   ./run.sh status     — статус процессов
#   ./run.sh client     — поднять клиентский Xray на локальной машине
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.env"
TMP_DIR="/tmp/xray-lab-variant-b"

# ── Загрузка переменных ────────────────────────────────────────────────────────

load_vars() {
    [[ -f "$VARS_FILE" ]] || {
        echo "ERROR: vars.env не найден — запусти: make init VAR=variant-b"
        exit 1
    }
    set -a; source "$VARS_FILE"; set +a
    # DOLLAR нужен для nginx.conf.tpl (экранирование nginx-переменных)
    export DOLLAR='$'
}

# ── Рендер шаблона ─────────────────────────────────────────────────────────────

render_json() {
    local tpl="$1" out="$2"
    envsubst < "$tpl" > "$out"
    echo "  rendered: $(basename "$tpl") → $out"
}

render_nginx() {
    local tpl="$1" out="$2"
    # Явный список переменных — nginx-переменные ($host и т.п.) не затрагиваются
    envsubst '${DOMAIN}${REALITY_INBOUND_PORT}${WS_INBOUND_PORT}${NGINX_HTTPS_PORT}${WS_PATH}${CERT_FILE}${KEY_FILE}${SUB_PATH}${DOLLAR}' \
        < "$tpl" > "$out"
    echo "  rendered: $(basename "$tpl") → $out"
}

# ── Проверки предусловий ────────────────────────────────────────────────────────

check_prereqs() {
    # Nginx stream module
    if ! nginx -V 2>&1 | grep -q "with-stream"; then
        echo "  [!] Nginx скомпилирован без --with-stream. Установи nginx-full:"
        echo "      apt install nginx-full"
        exit 1
    fi

    # Cert (warning, не fatal — Reality часть работает без него)
    if [[ ! -f "${CERT_FILE:-}" ]]; then
        echo "  [!] TLS-сертификат не найден: ${CERT_FILE:-не задан}"
        echo "      WS+HTTPS часть не запустится. Reality продолжает работать."
        echo "      Получить: certbot certonly --standalone -d ${DOMAIN:-your-domain.com}"
        CERT_MISSING=1
    else
        CERT_MISSING=0
    fi
}

# ── Команды ────────────────────────────────────────────────────────────────────

cmd_up() {
    load_vars
    mkdir -p "$TMP_DIR"

    check_prereqs

    echo "==> Рендер конфигов..."
    render_json  "${SCRIPT_DIR}/xray-server.json.tpl" "${TMP_DIR}/xray-server.json"

    echo "==> Валидация xray-server.json..."
    xray run -test -c "${TMP_DIR}/xray-server.json" \
        && echo "    [OK] конфиг валиден" \
        || { echo "    [FAIL] невалидный конфиг"; exit 1; }

    echo "==> Запуск Xray (два inbound: reality :${REALITY_INBOUND_PORT}, ws :${WS_INBOUND_PORT})..."
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

    if [[ "${CERT_MISSING:-0}" == "1" ]]; then
        echo "==> [SKIP] Nginx не запускается — сертификат отсутствует"
        echo "    Reality часть (порт ${REALITY_INBOUND_PORT}) работает напрямую."
        echo "    Для полного стека: получи сертификат и перезапусти ./run.sh up"
        return
    fi

    echo "==> Рендер nginx.conf..."
    render_nginx "${SCRIPT_DIR}/nginx.conf.tpl" "${TMP_DIR}/nginx.conf"

    echo "==> Запуск Nginx (stream :443 → reality+https)..."
    sudo nginx -t -c "${TMP_DIR}/nginx.conf" \
        && sudo nginx -c "${TMP_DIR}/nginx.conf" \
        && echo "    [OK] Nginx запущен (stream :443, HTTPS :${NGINX_HTTPS_PORT})" \
        || echo "    [FAIL] Nginx не стартовал — проверь ${TMP_DIR}/nginx.conf"
}

cmd_down() {
    echo "==> Остановка..."
    if [[ -f "${TMP_DIR}/xray.pid" ]]; then
        sudo kill "$(cat "${TMP_DIR}/xray.pid")" 2>/dev/null \
            && echo "    [OK] Xray остановлен"
        rm -f "${TMP_DIR}/xray.pid"
    fi
    # Останавливаем только наш nginx-инстанс через pid-файл
    local nginx_pid="${TMP_DIR}/nginx.pid"
    if [[ -f "${nginx_pid}" ]]; then
        sudo kill "$(cat "${nginx_pid}")" 2>/dev/null \
            && echo "    [OK] Nginx остановлен"
    else
        sudo nginx -s stop 2>/dev/null && echo "    [OK] Nginx остановлен" || true
    fi
}

cmd_client() {
    load_vars
    mkdir -p "$TMP_DIR"
    echo "==> Запуск клиентского Xray (Reality, SOCKS5 :${SOCKS_PORT})..."
    envsubst < "${SCRIPT_DIR}/xray-client.json.tpl" > "${TMP_DIR}/xray-client.json"
    xray run -c "${TMP_DIR}/xray-client.json"
}

cmd_logs() {
    tail -f "${TMP_DIR}/xray.log" 2>/dev/null \
        || echo "Логи не найдены — сначала ./run.sh up"
}

cmd_status() {
    echo "==> Xray:"
    if [[ -f "${TMP_DIR}/xray.pid" ]] && kill -0 "$(cat "${TMP_DIR}/xray.pid")" 2>/dev/null; then
        echo "    запущен (pid $(cat "${TMP_DIR}/xray.pid"))"
    else
        echo "    не запущен"
    fi
    echo "==> Ports:"
    ss -tlnp | grep -E ':443 |:8443|:7443|:9001|:10085' || echo "    ничего не слушает"
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
