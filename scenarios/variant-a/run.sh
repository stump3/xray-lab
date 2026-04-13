#!/usr/bin/env bash
# run.sh — управление стеком variant-a
# Использование:
#   ./run.sh up         — поднять xray (+ nginx если есть)
#   ./run.sh down       — остановить
#   ./run.sh restart    — перезапустить
#   ./run.sh logs       — хвост логов
#   ./run.sh status     — статус процессов
#   ./run.sh client     — поднять клиентский xray на локальной машине
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.env"
TMP_DIR="/tmp/xray-lab-variant-a"
export NGINX_PID="${TMP_DIR}/nginx.pid"

# ── Загрузка переменных ────────────────────────────────────────────────────────

load_vars() {
    [[ -f "$VARS_FILE" ]] || {
        echo "ERROR: vars.env не найден — запусти: make init"
        exit 1
    }
    set -a; source "$VARS_FILE"; set +a
}

# ── Рендер шаблона через envsubst ─────────────────────────────────────────────

render() {
    local tpl="$1" out="$2"
    envsubst < "$tpl" > "$out"
    echo "  rendered: $tpl → $out"
}

# ── Команды ───────────────────────────────────────────────────────────────────

cmd_up() {
    load_vars
    mkdir -p "$TMP_DIR"

    echo "==> Рендер конфигов..."
    render "${SCRIPT_DIR}/xray-server.json.tpl" "${TMP_DIR}/xray-server.json"

    # Валидация конфига до запуска
    mkdir -p /var/log/xray

    echo "==> Валидация xray-server.json..."
    xray run -test -c "${TMP_DIR}/xray-server.json" \
        && echo "    [OK] конфиг валиден" \
        || { echo "    [FAIL] невалидный конфиг"; exit 1; }

    echo "==> Запуск xray (сервер)..."
    # В тестовой среде запускаем от текущего пользователя, не через systemd
    sudo xray run -c "${TMP_DIR}/xray-server.json" &> "${TMP_DIR}/xray.log" &
    echo $! > "${TMP_DIR}/xray.pid"
    sleep 1

    if kill -0 "$(cat "${TMP_DIR}/xray.pid")" 2>/dev/null; then
        echo "    [OK] xray запущен (pid $(cat "${TMP_DIR}/xray.pid"))"
    else
        echo "    [FAIL] xray упал, смотри логи:"
        tail -20 "${TMP_DIR}/xray.log"
        exit 1
    fi

    # Nginx (опционально — только если установлен)
    if command -v nginx &>/dev/null; then
        render "${SCRIPT_DIR}/nginx.conf.tpl" "${TMP_DIR}/nginx.conf"
        sudo nginx -t -c "${TMP_DIR}/nginx.conf" \
            && sudo nginx -c "${TMP_DIR}/nginx.conf" \
            && echo "    [OK] nginx запущен на порту ${NGINX_PORT:-8080}"
    else
        echo "    [SKIP] nginx не найден — subscription endpoint недоступен"
    fi
}

cmd_down() {
    echo "==> Остановка..."
    if [[ -f "${TMP_DIR}/xray.pid" ]]; then
        sudo kill "$(cat "${TMP_DIR}/xray.pid")" 2>/dev/null && echo "    [OK] xray остановлен"
        rm -f "${TMP_DIR}/xray.pid"
    fi
    # Останавливаем только наш nginx-инстанс через pid-файл
    local nginx_pid="${TMP_DIR}/nginx.pid"
    if [[ -f "$nginx_pid" ]]; then
        sudo kill "$(cat "$nginx_pid")" 2>/dev/null && echo "    [OK] nginx остановлен"
        rm -f "$nginx_pid"
    else
        echo "    [–] nginx не запущен (pid-файл не найден)"
    fi
}

cmd_client() {
    load_vars
    mkdir -p "$TMP_DIR"
    echo "==> Запуск клиентского xray (SOCKS5 на 127.0.0.1:${SOCKS_PORT:-1080})..."
    render "${SCRIPT_DIR}/xray-client.json.tpl" "${TMP_DIR}/xray-client.json"
    xray run -c "${TMP_DIR}/xray-client.json"
}

cmd_logs() {
    tail -f "${TMP_DIR}/xray.log" 2>/dev/null || echo "Логи не найдены — сначала ./run.sh up"
}

cmd_status() {
    echo "==> Xray:"
    if [[ -f "${TMP_DIR}/xray.pid" ]] && kill -0 "$(cat "${TMP_DIR}/xray.pid")" 2>/dev/null; then
        echo "    запущен (pid $(cat "${TMP_DIR}/xray.pid"))"
    else
        echo "    не запущен"
    fi
    echo "==> Ports:"
    ss -tlnp | grep -E ':443|:10085|:8080' || echo "    ничего не слушает"
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
