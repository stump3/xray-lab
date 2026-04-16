#!/usr/bin/env bash
# run.sh — управление стеком variant-c2 (All-in-One, 17 протоколов)
# Использование:
#   ./run.sh up       — Nginx (оба сокета) → Xray (:443, TLS, fallbacks)
#   ./run.sh down     — остановить всё, почистить сокеты
#   ./run.sh restart  — перезапустить
#   ./run.sh logs     — хвост логов Xray
#   ./run.sh status   — статус процессов и портов
#   ./run.sh client   — клиентский Xray (VLESS+Vision+TLS, SOCKS5)
#
# ВАЖНО: Nginx стартует первым — он создаёт unix-сокеты h1.sock и h2c.sock.
# Xray стартует вторым — он пишет в эти сокеты. Если порядок обратный — Xray упадёт.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.env"
TMP_DIR="/tmp/xray-lab-variant-c2"

load_vars() {
    [[ -f "$VARS_FILE" ]] || {
        echo "ERROR: vars.env не найден — запусти: make init VAR=variant-c2"
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
    # Явный список переменных — не трогаем nginx-переменные ($host, $uri и т.д.)
    envsubst '${NGINX_PID}${H1_SOCK}${H2C_SOCK}${DOMAIN}${SUB_PATH}${DOLLAR}
              ${TROJAN_GRPC_SVC}${VLESS_GRPC_SVC}${VMESS_GRPC_SVC}${SS_GRPC_SVC}
              ${TROJAN_GRPC_PORT}${VLESS_GRPC_PORT}${VMESS_GRPC_PORT}${SS_GRPC_PORT}' \
        < "$tpl" > "$out"
    echo "  rendered: $(basename "$tpl") → $out"
}

release_port() {
    local port="$1" silent=0
    [[ "${2:-}" == "--silent" ]] && silent=1
    local pids
    mapfile -t pids < <(ss -tlnp "sport = :${port}" 2>/dev/null \
        | awk 'NR>1 { while (match($0, /pid=([0-9]+)/, a)) { print a[1]; $0=substr($0, RSTART+RLENGTH) } }' \
        | sort -u)
    [[ ${#pids[@]} -eq 0 ]] && return 0
    if (( silent == 0 )); then
        local names=""
        for pid in "${pids[@]}"; do
            names+="$(ps -p "$pid" -o comm= 2>/dev/null || echo '?')(${pid}) "
        done
        echo "  [!] Порт :${port} занят (${names}) — завершаем"
    fi
    for pid in "${pids[@]}"; do sudo kill "$pid" 2>/dev/null || true; done
    local w=0
    while ss -tlnp "sport = :${port}" 2>/dev/null | grep -q ":${port}"; do
        sleep 0.3; (( w++ ))
        (( w >= 15 )) && { echo "  [✗] Порт :${port} не освобождается" >&2; return 1; }
    done
    (( silent == 0 )) && echo "  [✓] Порт :${port} освобождён"
    return 0
}

wait_for_sock() {
    local sock="$1" label="$2" retries=0
    while [[ ! -S "$sock" ]] && (( retries < 20 )); do
        sleep 0.3; (( retries++ ))
    done
    if [[ -S "$sock" ]]; then
        echo "    [OK] unix socket готов: $sock ($label)"
    else
        echo "    [FAIL] unix socket не появился: $sock ($label)" >&2
        return 1
    fi
}

check_prereqs() {
    if [[ ! -f "${CERT_FILE:-}" ]]; then
        echo "  [✗] TLS-сертификат не найден: ${CERT_FILE:-не задан}"
        echo "      Нужен wildcard cert. Пример:"
        echo "      certbot certonly --standalone -d ${DOMAIN:-your-domain.com} -d *.${DOMAIN:-your-domain.com}"
        exit 1
    fi
    [[ -d /dev/shm ]] || { echo "  [✗] /dev/shm недоступен"; exit 1; }

    # Проверить Nginx с нужными модулями
    if ! command -v nginx &>/dev/null; then
        echo "  [✗] nginx не найден"
        exit 1
    fi
    if ! nginx -V 2>&1 | grep -q "http_v2_module"; then
        echo "  [!] nginx собран без http_v2_module — h2c.sock (gRPC) не будет работать"
    fi
}

cmd_up() {
    load_vars
    mkdir -p "$TMP_DIR"
    check_prereqs

    echo "==> Рендер конфигов..."
    render_json  "${SCRIPT_DIR}/xray-server.json.tpl" "${TMP_DIR}/xray-server.json"
    render_nginx "${SCRIPT_DIR}/nginx.conf.tpl"        "${TMP_DIR}/nginx.conf"

    mkdir -p /var/log/xray

    echo "==> Валидация xray-server.json..."
    xray run -test -c "${TMP_DIR}/xray-server.json" \
        && echo "    [OK] конфиг валиден" \
        || { echo "    [FAIL] невалидный конфиг"; exit 1; }

    echo "==> Запуск Nginx (h1.sock + h2c.sock)..."
    # Убираем старые сокеты если остались
    rm -f "${H1_SOCK}" "${H2C_SOCK}"

    sudo nginx -t -c "${TMP_DIR}/nginx.conf" \
        && sudo nginx -c "${TMP_DIR}/nginx.conf" \
        && echo "    [OK] Nginx запущен" \
        || { echo "    [FAIL] Nginx не стартовал"; exit 1; }

    wait_for_sock "${H1_SOCK}"  "HTTP/1.1 decoy"
    wait_for_sock "${H2C_SOCK}" "HTTP/2 gRPC routing"

    release_port 443

    echo "==> Запуск Xray (:443, TLS+Vision, fallbacks → 17 протоколов)..."
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
    echo "  Xray:       :443  (VLESS+Vision+TLS, fallbacks)"
    echo "  Nginx h1:   unix:${H1_SOCK}  (decoy + /sub)"
    echo "  Nginx h2c:  unix:${H2C_SOCK} (gRPC routing)"
    echo "  API:        127.0.0.1:${API_PORT}"
    echo "  gRPC ports: :${TROJAN_GRPC_PORT} :${VLESS_GRPC_PORT} :${VMESS_GRPC_PORT} :${SS_GRPC_PORT}"
    echo "  SS ports:   :${SS_WS_PORT} :${SS_TC_PORT} :${SS_XHTTP_PORT}"
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
    release_port 443 --silent
    rm -f "${H1_SOCK:-/dev/shm/xraylab-c2-h1.sock}"
    rm -f "${H2C_SOCK:-/dev/shm/xraylab-c2-h2c.sock}"
}

cmd_client() {
    load_vars
    mkdir -p "$TMP_DIR"
    echo "==> Запуск клиентского Xray (VLESS+Vision+TLS, SOCKS5 :${SOCKS_PORT})..."
    envsubst < "${SCRIPT_DIR}/xray-client.json.tpl" > "${TMP_DIR}/xray-client.json"
    xray run -c "${TMP_DIR}/xray-client.json"
}

cmd_logs() {
    tail -f "${TMP_DIR}/xray.log" 2>/dev/null \
        || echo "Логи не найдены — сначала ./run.sh up"
}

cmd_status() {
    load_vars 2>/dev/null || true
    echo "==> Xray:"
    if [[ -f "${TMP_DIR}/xray.pid" ]] && kill -0 "$(cat "${TMP_DIR}/xray.pid")" 2>/dev/null; then
        echo "    запущен (pid $(cat "${TMP_DIR}/xray.pid"))"
    else
        echo "    не запущен"
    fi
    echo "==> Unix sockets:"
    for sock in "${H1_SOCK:-/dev/shm/xraylab-c2-h1.sock}" \
                "${H2C_SOCK:-/dev/shm/xraylab-c2-h2c.sock}"; do
        [[ -S "$sock" ]] && echo "    ✓ $sock" || echo "    ✗ $sock"
    done
    echo "==> Ports:"
    ss -tlnp | grep -E ':443 |:3001|:3002|:3003|:3004|:4001|:4002|:4003|:62789' \
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
