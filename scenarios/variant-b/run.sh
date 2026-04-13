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
    envsubst '${DOMAIN}${REALITY_INBOUND_PORT}${WS_INBOUND_PORT}${NGINX_HTTPS_PORT}${WS_PATH}${CERT_FILE}${KEY_FILE}${SUB_PATH}${NGINX_PID}${DOLLAR}' \
        < "$tpl" > "$out"
    echo "  rendered: $(basename "$tpl") → $out"
}

# ── release_port PORT [--silent] ───────────────────────────────────────────────
# Завершает ВСЕ процессы на порту без интерактивных вопросов.
# cmd_up: выводит предупреждение и завершает автоматически.
# cmd_down: тихий режим (--silent) — просто чистит без вывода.

release_port() {
    local port="$1" silent=0
    [[ "${2:-}" == "--silent" ]] && silent=1

    local pids
    mapfile -t pids < <(ss -tlnp "sport = :${port}" 2>/dev/null \
        | awk 'NR>1 { while (match($0, /pid=([0-9]+)/, a)) { print a[1]; $0=substr($0, RSTART+RLENGTH) } }' \
        | sort -u)

    [[ ${#pids[@]} -eq 0 ]] && return 0

    if (( silent == 0 )); then
        local proc_list=""
        for pid in "${pids[@]}"; do
            local name; name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "?")
            proc_list+="${name}(${pid}) "
        done
        echo "  [!] Порт :${port} занят (${proc_list}) — завершаем автоматически"
    fi

    for pid in "${pids[@]}"; do
        sudo kill "$pid" 2>/dev/null || true
    done

    local waited=0
    while ss -tlnp "sport = :${port}" 2>/dev/null | grep -q ":${port}"; do
        sleep 0.3; (( waited++ ))
        if (( waited >= 15 )); then
            echo "  [✗] Порт :${port} не освобождается — попробуй: fuser -k ${port}/tcp" >&2
            return 1
        fi
    done
    (( silent == 0 )) && echo "  [✓] Порт :${port} освобождён"
    return 0
}

# ── Проверки предусловий ───────────────────────────────────────────────────────

check_prereqs() {
    local has_stream=0
    nginx -V 2>&1 | grep -q "with-stream" && has_stream=1
    [[ -f /usr/lib/nginx/modules/ngx_stream_module.so ]] && has_stream=1
    if (( has_stream == 0 )); then
        echo "  [!] Nginx без модуля stream. Установи nginx-full:"
        echo "      apt install nginx-full"
        exit 1
    fi

    if [[ ! -f "${CERT_FILE:-}" ]]; then
        echo "  [!] TLS-сертификат не найден: ${CERT_FILE:-не задан}"
        echo "      WS+HTTPS часть не запустится. Reality продолжает работать."
        echo "      Получить: certbot certonly --standalone -d ${DOMAIN:-your-domain.com}"
        CERT_MISSING=1
    else
        CERT_MISSING=0
    fi
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
        return
    fi

    echo "==> Рендер nginx.conf..."
    render_nginx "${SCRIPT_DIR}/nginx.conf.tpl" "${TMP_DIR}/nginx.conf"

    # Освобождаем :443 автоматически (без вопросов) перед запуском Nginx
    release_port 443

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

    local npid="${TMP_DIR}/nginx.pid"
    if [[ -f "$npid" ]]; then
        sudo kill "$(cat "$npid")" 2>/dev/null \
            && echo "    [OK] Nginx остановлен"
        rm -f "$npid"
    fi

    # Финальная чистка — убиваем всё что ещё держит :443 (тихо)
    release_port 443 --silent
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
    ss -tlnp | grep -E ':443 |:'"${REALITY_INBOUND_PORT:-8443}"'|:'"${WS_INBOUND_PORT:-9001}"'|:10085' \
        || echo "    ничего не слушает"
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
