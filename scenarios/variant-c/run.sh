#!/usr/bin/env bash
# run.sh — управление стеком variant-c (Xray native fallbacks, All-in-One)
# Использование:
#   ./run.sh up         — поднять Xray (:443, TLS, fallbacks) + Nginx (unix socket)
#   ./run.sh down       — остановить всё
#   ./run.sh restart    — перезапустить
#   ./run.sh logs       — хвост логов Xray
#   ./run.sh status     — статус процессов
#   ./run.sh client     — поднять клиентский Xray (WS+TLS, SOCKS5)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.env"
TMP_DIR="/tmp/xray-lab-variant-c"

# ── Загрузка переменных ────────────────────────────────────────────────────────

load_vars() {
    [[ -f "$VARS_FILE" ]] || {
        echo "ERROR: vars.env не найден — запусти: make init VAR=variant-c"
        exit 1
    }
    set -a; source "$VARS_FILE"; set +a
    # DOLLAR — для экранирования nginx-переменных в шаблоне
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
    # Явный список — nginx-переменные ($uri и т.п.) не затрагиваются
    envsubst '${DOMAIN}${H1_SOCK}${SUB_PATH}${DOLLAR}${NGINX_PID}' \
        < "$tpl" > "$out"
    echo "  rendered: $(basename "$tpl") → $out"
}

# ── Утилиты ────────────────────────────────────────────────────────────────────

release_port() {
    local port="$1"
    local pid proc
    pid=$(ss -tlnp "sport = :${port}" 2>/dev/null \
        | awk 'NR>1 { match($0, /pid=([0-9]+)/, a); if (a[1]) print a[1] }' \
        | head -1)
    [[ -z "$pid" ]] && return 0
    proc=$(ps -p "$pid" -o comm= 2>/dev/null || echo "?")
    echo "  [!] Порт :${port} занят: ${proc} (pid ${pid})"
    printf "      Завершить %s? [y/N] " "$proc"
    read -r reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        sudo kill "$pid" 2>/dev/null || true
        sleep 0.5
        echo "  [✓] Процесс ${pid} завершён"
    else
        echo "  [✗] Порт :${port} занят — останови конфликт вручную и повтори" >&2
        exit 1
    fi
}

# ── Проверки предусловий ───────────────────────────────────────────────────────

check_prereqs() {
    # TLS-сертификат обязателен для Variant C
    if [[ ! -f "${CERT_FILE:-}" ]]; then
        echo "  [✗] TLS-сертификат не найден: ${CERT_FILE:-не задан}"
        echo "      Variant C требует сертификат. Получить:"
        echo "      certbot certonly --standalone -d ${DOMAIN:-your-domain.com}"
        exit 1
    fi

    # /dev/shm должен быть доступен (tmpfs для unix socket)
    [[ -d /dev/shm ]] || {
        echo "  [✗] /dev/shm недоступен — unix socket не создать"
        exit 1
    }
}

# ── Команды ───────────────────────────────────────────────────────────────────

cmd_up() {
    load_vars
    mkdir -p "$TMP_DIR"
    check_prereqs

    echo "==> Рендер конфигов..."
    render_json "${SCRIPT_DIR}/xray-server.json.tpl" "${TMP_DIR}/xray-server.json"

    mkdir -p /var/log/xray

    echo "==> Валидация xray-server.json..."
    xray run -test -c "${TMP_DIR}/xray-server.json" \
        && echo "    [OK] конфиг валиден" \
        || { echo "    [FAIL] невалидный конфиг"; exit 1; }

    echo "==> Рендер nginx.conf..."
    render_nginx "${SCRIPT_DIR}/nginx.conf.tpl" "${TMP_DIR}/nginx.conf"

    echo "==> Запуск Nginx (unix socket: ${H1_SOCK})..."
    sudo nginx -t -c "${TMP_DIR}/nginx.conf" \
        && sudo nginx -c "${TMP_DIR}/nginx.conf" \
        && echo "    [OK] Nginx запущен (unix:${H1_SOCK})" \
        || { echo "    [FAIL] Nginx не стартовал"; exit 1; }

    # Ждём появления unix socket перед запуском Xray (fallback пишет туда сразу)
    local retries=0
    while [[ ! -S "${H1_SOCK}" ]] && (( retries < 10 )); do
        sleep 0.5; (( retries++ ))
    done
    if [[ ! -S "${H1_SOCK}" ]]; then
        echo "    [FAIL] unix socket не появился: ${H1_SOCK}"
        exit 1
    fi
    echo "    [OK] unix socket готов: ${H1_SOCK}"

    echo "==> Запуск Xray (:443, TLS, fallbacks → WS inbounds + unix socket)..."
    release_port 443
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
    echo "  Xray:  :443 (VLESS+TLS, fallbacks → sub-inbounds)"
    echo "  VLESS WS: 127.0.0.1:${VLESS_WS_PORT}  path=${VLESS_WS_PATH}"
    echo "  VMess WS: 127.0.0.1:${VMESS_WS_PORT}  path=${VMESS_WS_PATH}"
    echo "  Decoy:    unix:${H1_SOCK} (Nginx)"
    echo "  Stats API: 127.0.0.1:10085"
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
        rm -f "$npid"
    else
        echo "    [–] Nginx не запущен (pid-файл не найден)"
    fi
    # Чистим unix socket
    rm -f "${H1_SOCK:-/dev/shm/xraylab-c-h1.sock}"
}

cmd_client() {
    load_vars
    mkdir -p "$TMP_DIR"
    echo "==> Запуск клиентского Xray (VLESS+WS+TLS, SOCKS5 :${SOCKS_PORT})..."
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
    echo "==> Unix socket:"
    local sock="${H1_SOCK:-/dev/shm/xraylab-c-h1.sock}"
    [[ -S "$sock" ]] && echo "    существует: $sock" || echo "    отсутствует: $sock"
    echo "==> Ports:"
    ss -tlnp | grep -E ':443 |:9001|:9002|:10085' || echo "    ничего не слушает"
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
