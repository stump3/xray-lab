#!/usr/bin/env bash
# test.sh — проверка стека variant-a
# Запускать ПОСЛЕ ./run.sh up (сервер) и ./run.sh client (клиент в отдельном терминале)
#
# Использование:
#   ./test.sh              — все проверки
#   ./test.sh server       — только серверная сторона
#   ./test.sh proxy        — только проверка проксирования через SOCKS5
#   ./test.sh domain       — проверить пригодность REALITY_DOMAIN
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.env"

[[ -f "$VARS_FILE" ]] && { set -a; source "$VARS_FILE"; set +a; }

SOCKS="${SOCKS_PORT:-1080}"
PORT="${XRAY_PORT:-443}"
PASS=0; FAIL=0

# ── Хелперы ───────────────────────────────────────────────────────────────────

ok()   { echo "  [PASS] $*"; (( PASS++ )) || true; }
fail() { echo "  [FAIL] $*"; (( FAIL++ )) || true; }
info() { echo "  [INFO] $*"; }
section() { echo; echo "── $* ─────────────────────────────────────────"; }

# ── Серверные тесты (запускать на сервере) ────────────────────────────────────

test_server() {
    section "Сервер"

    # 1. Xray слушает на нужном порту
    if ss -tlnp "sport = :${PORT}" 2>/dev/null | grep -q LISTEN; then
        ok "Xray слушает на :${PORT}"
    else
        fail "Xray НЕ слушает на :${PORT}"
    fi

    # 2. Stats API отвечает
    if curl -s --max-time 2 "http://127.0.0.1:10085" &>/dev/null; then
        ok "Stats API доступен на :10085"
    else
        info "Stats API не ответил (это нормально если dokodemo не настроен как http)"
    fi

    # 3. Конфиг валиден (перепроверка без перезапуска)
    local conf="/tmp/xray-lab-variant-a/xray-server.json"
    if [[ -f "$conf" ]]; then
        if xray run -test -c "$conf" &>/dev/null; then
            ok "xray -test: конфиг валиден"
        else
            fail "xray -test: ошибки в конфиге"
            xray run -test -c "$conf" 2>&1 | head -10
        fi
    else
        info "Рендеренный конфиг не найден — запусти ./run.sh up"
    fi

    # 4. Reality: TLS-ответ от сервера выглядит как decoy domain
    if command -v openssl &>/dev/null; then
        local sni_resp
        sni_resp=$(echo | timeout 5 openssl s_client \
            -connect "127.0.0.1:${PORT}" \
            -servername "${REALITY_DOMAIN:-www.microsoft.com}" \
            2>/dev/null | grep "subject=" | head -1) || true
        if [[ -n "$sni_resp" ]]; then
            ok "TLS handshake прошёл: $sni_resp"
        else
            fail "TLS handshake не прошёл (xray не запущен или порт неверный)"
        fi
    fi
}

# ── Тесты decoy-домена ────────────────────────────────────────────────────────

test_domain() {
    section "Reality domain: ${REALITY_DOMAIN:-не задан}"
    local domain="${REALITY_DOMAIN:-www.microsoft.com}"

    # Не Cloudflare?
    local headers
    headers=$(curl -fsSL -I --max-time 5 "https://$domain" 2>/dev/null | tr '[:upper:]' '[:lower:]') || true
    if echo "$headers" | grep -q "cf-ray:"; then
        fail "$domain использует Cloudflare — Reality с ним несовместима"
    else
        ok "$domain не использует Cloudflare"
    fi

    # TLS 1.3?
    local code
    code=$(curl -fsSL --tlsv1.3 --tls-max 1.3 --max-time 5 \
        -o /dev/null -w "%{http_code}" "https://$domain" 2>/dev/null) || code=0
    if [[ "$code" =~ ^[1-9] ]]; then
        ok "$domain поддерживает TLS 1.3 (HTTP $code)"
    else
        fail "$domain не поддерживает TLS 1.3"
    fi

    # HTTP/2?
    if curl -fsSL --http2 -v --max-time 5 -o /dev/null \
        "https://$domain" 2>&1 | grep -q "< HTTP/2"; then
        ok "$domain поддерживает HTTP/2"
    else
        fail "$domain не поддерживает HTTP/2"
    fi
}

# ── Тесты проксирования (запускать на клиентской машине) ──────────────────────

test_proxy() {
    section "Проксирование через SOCKS5 127.0.0.1:${SOCKS}"

    # 1. Клиентский xray слушает SOCKS5
    if ss -tlnp "sport = :${SOCKS}" 2>/dev/null | grep -q LISTEN; then
        ok "SOCKS5 слушает на :${SOCKS}"
    else
        fail "SOCKS5 НЕ слушает на :${SOCKS} — запусти ./run.sh client"
        return
    fi

    # 2. Получить внешний IP через прокси
    local ext_ip
    ext_ip=$(curl -fsSL --max-time 10 \
        --proxy "socks5h://127.0.0.1:${SOCKS}" \
        "https://icanhazip.com" 2>/dev/null) || ext_ip=""
    if [[ -n "$ext_ip" ]]; then
        ok "Внешний IP через прокси: ${ext_ip} (должен совпадать с SERVER_IP=${SERVER_IP:-?})"
    else
        fail "Не удалось получить внешний IP через прокси"
    fi

    # 3. Запрос к google через прокси
    local gcode
    gcode=$(curl -fsSL --max-time 10 \
        --proxy "socks5h://127.0.0.1:${SOCKS}" \
        -o /dev/null -w "%{http_code}" \
        "https://www.google.com" 2>/dev/null) || gcode=0
    if [[ "$gcode" =~ ^[1-9] ]]; then
        ok "google.com через прокси: HTTP $gcode"
    else
        fail "google.com через прокси недоступен"
    fi

    # 4. DNS leak check — убеждаемся что резолвится через сервер
    local dns_ip
    dns_ip=$(curl -fsSL --max-time 10 \
        --proxy "socks5h://127.0.0.1:${SOCKS}" \
        "https://dns.google/resolve?name=ifconfig.me&type=A" 2>/dev/null \
        | grep -oP '"data":"\K[^"]+' | head -1) || dns_ip=""
    if [[ -n "$dns_ip" ]]; then
        ok "DNS резолвится через прокси: ifconfig.me → $dns_ip"
    else
        info "DNS leak check пропущен (jq/curl недоступен)"
    fi
}

# ── Итог ──────────────────────────────────────────────────────────────────────

summary() {
    echo
    echo "══════════════════════════════════════"
    echo "  PASS: ${PASS}   FAIL: ${FAIL}"
    echo "══════════════════════════════════════"
    (( FAIL == 0 )) && exit 0 || exit 1
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

case "${1:-all}" in
    server) test_server; summary ;;
    domain) test_domain; summary ;;
    proxy)  test_proxy;  summary ;;
    all)
        test_server
        test_domain
        test_proxy
        summary
        ;;
    *)
        echo "Использование: $0 {all|server|domain|proxy}"
        exit 1
        ;;
esac
