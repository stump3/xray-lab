#!/usr/bin/env bash
# run.sh — управление стеком variant-b2 (Nginx stream SNI + Hysteria2)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.env"
TMP_DIR="/tmp/xray-lab-variant-b2"

load_vars() {
    [[ -f "$VARS_FILE" ]] || {
        echo "ERROR: vars.env не найден — запусти: make init VAR=variant-b2"
        exit 1
    }
    set -a; source "$VARS_FILE"; set +a
    export DOLLAR='$'
    export NGINX_PID="${TMP_DIR}/nginx.pid"
}

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

release_port() {
    local port="$1" proto="${2:-tcp}" silent=0
    [[ "${3:-}" == "--silent" || "${2:-}" == "--silent" ]] && silent=1

    local ss_filter
    [[ "$proto" == "udp" ]] \
        && ss_filter="ss -ulnp sport = :${port}" \
        || ss_filter="ss -tlnp sport = :${port}"

    local pids
    mapfile -t pids < <($ss_filter 2>/dev/null \
        | awk 'NR>1 { while (match($0, /pid=([0-9]+)/, a)) { print a[1]; $0=substr($0, RSTART+RLENGTH) } }' \
        | sort -u)
    [[ ${#pids[@]} -eq 0 ]] && return 0

    if (( silent == 0 )); then
        local names=""
        for pid in "${pids[@]}"; do
            names+="$(ps -p "$pid" -o comm= 2>/dev/null || echo '?')(${pid}) "
        done
        echo "  [!] Порт :${port}/${proto} занят (${names}) — завершаем"
    fi
    for pid in "${pids[@]}"; do sudo kill "$pid" 2>/dev/null || true; done

    # Ждём только для TCP (UDP release мгновенный)
    if [[ "$proto" == "tcp" ]]; then
        local w=0
        while ss -tlnp "sport = :${port}" 2>/dev/null | grep -q ":${port}"; do
            sleep 0.3; (( w++ ))
            (( w >= 15 )) && { echo "  [✗] Порт :${port}/tcp не освобождается" >&2; return 1; }
        done
    fi
    (( silent == 0 )) && echo "  [✓] Порт :${port}/${proto} освобождён"
}

check_prereqs() {
    # Nginx stream module
    local has_stream=0
    nginx -V 2>&1 | grep -q "with-stream" && has_stream=1
    [[ -f /usr/lib/nginx/modules/ngx_stream_module.so ]] && has_stream=1
    if (( has_stream == 0 )); then
        echo "  [✗] Nginx без модуля stream. Установи: apt install nginx-full"
        exit 1
    fi

    # TLS сертификат для Nginx+WS
    if [[ ! -f "${CERT_FILE:-}" ]]; then
        warn "  [!] Сертификат Nginx не найден: ${CERT_FILE:-не задан}"
        warn "      WS+HTTPS часть не запустится."
        warn "      Получить: certbot certonly --standalone -d ${DOMAIN:-your-domain.com}"
        CERT_MISSING=1
    else
        CERT_MISSING=0
    fi

    # TLS сертификат для Hysteria2
    if [[ ! -f "${H2_CERT_FILE:-}" ]]; then
        warn "  [!] Сертификат Hysteria2 не найден: ${H2_CERT_FILE:-не задан}"
        warn "      Hysteria2 не запустится."
        warn "      Получить: certbot certonly --standalone -d ${H2_DOMAIN:-your-domain.com}"
        H2_CERT_MISSING=1
    else
        H2_CERT_MISSING=0
    fi
}

cmd_up() {
    load_vars
    mkdir -p "$TMP_DIR" /var/log/xray
    check_prereqs

    echo "==> Рендер конфигов..."
    render_json "${SCRIPT_DIR}/xray-server.json.tpl" "${TMP_DIR}/xray-server.json"

    echo "==> Валидация xray-server.json..."
    xray run -test -c "${TMP_DIR}/xray-server.json" \
        && echo "    [OK] конфиг валиден" \
        || { echo "    [FAIL] невалидный конфиг"; exit 1; }

    # Xray стартует первым: Reality + WS (TCP loopback) + Hysteria2 (UDP:443)
    echo "==> Запуск Xray (Reality :${REALITY_INBOUND_PORT}, WS :${WS_INBOUND_PORT}, H2 UDP:443)..."
    release_port 443 udp
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
        echo "==> [SKIP] Nginx — сертификат отсутствует"
    else
        echo "==> Рендер nginx.conf..."
        render_nginx "${SCRIPT_DIR}/nginx.conf.tpl" "${TMP_DIR}/nginx.conf"
        release_port 443 tcp
        release_port "${NGINX_HTTPS_PORT}"
        echo "==> Запуск Nginx (stream TCP:443)..."
        sudo nginx -t -c "${TMP_DIR}/nginx.conf" \
            && sudo nginx -c "${TMP_DIR}/nginx.conf" \
            && echo "    [OK] Nginx запущен (stream :443, HTTPS :${NGINX_HTTPS_PORT})" \
            || echo "    [FAIL] Nginx не стартовал"
    fi

    echo
    echo "  TCP:443 → Nginx stream SNI → Reality :${REALITY_INBOUND_PORT} / WS :${WS_INBOUND_PORT}"
    echo "  UDP:443 → Xray Hysteria2  (домен: ${H2_DOMAIN:-?})"
    [[ "${H2_CERT_MISSING:-0}" == "1" ]] && echo "  [!] Hysteria2: сертификат не найден — клиенты подключиться не смогут"
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
    release_port 443 tcp --silent
}

cmd_client() {
    load_vars
    mkdir -p "$TMP_DIR"
    echo "==> Запуск клиентского Xray (Reality, SOCKS5 :${SOCKS_PORT})..."
    envsubst < "${SCRIPT_DIR}/xray-client.json.tpl" > "${TMP_DIR}/xray-client.json"
    xray run -c "${TMP_DIR}/xray-client.json"
}

cmd_logs()   { tail -f "${TMP_DIR}/xray.log" 2>/dev/null || echo "Логи не найдены"; }

cmd_status() {
    load_vars 2>/dev/null || true
    echo "==> Xray:"
    if [[ -f "${TMP_DIR}/xray.pid" ]] && kill -0 "$(cat "${TMP_DIR}/xray.pid")" 2>/dev/null; then
        echo "    запущен (pid $(cat "${TMP_DIR}/xray.pid"))"
    else
        echo "    не запущен"
    fi
    echo "==> Ports (TCP):"
    ss -tlnp | grep -E ':443 |:'${REALITY_INBOUND_PORT:-8443}'|:'${WS_INBOUND_PORT:-9001}'|:10085' \
        || echo "    ничего не слушает"
    echo "==> Ports (UDP — Hysteria2):"
    ss -ulnp | grep ':443' || echo "    UDP:443 не слушает"
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
