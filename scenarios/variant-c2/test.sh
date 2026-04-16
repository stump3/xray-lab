#!/usr/bin/env bash
# test.sh — проверка стека variant-c2 (All-in-One, 17 протоколов)
# Использование:
#   ./test.sh              — все проверки
#   ./test.sh server       — порты, сокеты, конфиг
#   ./test.sh fallback     — TLS handshake + fallback на decoy
#   ./test.sh domain       — сертификат
#   ./test.sh proxy        — проксирование через SOCKS5 (VLESS+Vision)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.env"

[[ -f "$VARS_FILE" ]] && { set -a; source "$VARS_FILE"; set +a; }

SOCKS="${SOCKS_PORT:-1080}"
PASS=0; FAIL=0; SKIP=0

ok()      { echo "  [PASS] $*"; (( PASS++ )) || true; }
fail()    { echo "  [FAIL] $*"; (( FAIL++ )) || true; }
skip()    { echo "  [SKIP] $*"; (( SKIP++ )) || true; }
info()    { echo "  [INFO] $*"; }
section() { echo; echo "── $* ─────────────────────────────────────────"; }

check_port() {
    local port="$1" label="$2"
    if ss -tlnp "sport = :${port}" 2>/dev/null | grep -q LISTEN; then
        ok "${label} слушает :${port}"
    else
        fail "${label} НЕ слушает :${port}"
    fi
}

check_sock() {
    local sock="$1" label="$2"
    if [[ -S "$sock" ]]; then
        ok "Unix socket существует: $sock ($label)"
    else
        fail "Unix socket отсутствует: $sock ($label)"
    fi
}

test_server() {
    section "Сервер: порты и сокеты"

    check_port 443           "Xray main inbound"
    check_port "${API_PORT:-62789}" "Stats API"

    # gRPC inbounds
    check_port "${TROJAN_GRPC_PORT:-3001}" "Trojan gRPC"
    check_port "${VLESS_GRPC_PORT:-3002}"  "VLESS gRPC"
    check_port "${VMESS_GRPC_PORT:-3003}"  "VMess gRPC"
    check_port "${SS_GRPC_PORT:-3004}"     "SS gRPC"

    # SS sub-inbounds
    check_port "${SS_WS_PORT:-4001}" "SS WebSocket"
    check_port "${SS_TC_PORT:-4002}" "SS TCP obfs"
    check_port "${SS_XHTTP_PORT:-4003}" "SS XHTTP"

    # Unix sockets
    check_sock "${H1_SOCK:-/dev/shm/xraylab-c2-h1.sock}"  "HTTP/1.1 decoy"
    check_sock "${H2C_SOCK:-/dev/shm/xraylab-c2-h2c.sock}" "HTTP/2 gRPC routing"

    # Конфиг
    local conf="/tmp/xray-lab-variant-c2/xray-server.json"
    if [[ -f "$conf" ]]; then
        xray run -test -c "$conf" &>/dev/null \
            && ok "xray -test: конфиг валиден" \
            || fail "xray -test: ошибки в конфиге"
    else
        info "Рендеренный конфиг не найден — запусти make up VAR=variant-c2"
    fi
}

test_fallback() {
    section "Fallback маршрутизация"

    local domain="${DOMAIN:-your-domain.com}"
    local cert="${CERT_FILE:-}"

    if [[ ! -f "$cert" ]]; then
        skip "TLS-сертификат не найден — тесты fallback пропущены"
        return
    fi

    # TLS handshake — должен вернуть наш сертификат
    local subj
    subj=$(echo | timeout 5 openssl s_client \
        -connect "127.0.0.1:443" -servername "$domain" \
        2>/dev/null | grep "subject=" | head -1) || subj=""

    if echo "$subj" | grep -qi "$domain"; then
        ok "TLS :443 → наш сертификат (${domain})"
    elif [[ -n "$subj" ]]; then
        info "TLS :443 → другой CN: $subj"
    else
        fail "TLS :443 → handshake не прошёл"
    fi

    # Default fallback → Nginx h1.sock → decoy сайт
    local code
    code=$(curl -fsSk --max-time 5 -o /dev/null -w "%{http_code}" \
        "https://127.0.0.1:443/" -H "Host: ${domain}" 2>/dev/null) || code=0
    if [[ "$code" =~ ^[1-9] ]]; then
        ok "Default fallback → Nginx h1.sock → HTTP ${code}"
    else
        info "Default fallback → нет HTTP-ответа (${code})"
    fi

    # WS path fallback
    local ws_code
    ws_code=$(curl -fsSk --max-time 5 -o /dev/null -w "%{http_code}" \
        --http1.1 \
        -H "Upgrade: websocket" -H "Connection: Upgrade" \
        -H "Host: ${domain}" \
        "https://127.0.0.1:443${VLESS_WS_PATH:-/vlws}" 2>/dev/null) || ws_code=0
    if [[ "$ws_code" == "101" || "$ws_code" == "400" ]]; then
        ok "WS path fallback → sub-inbound (HTTP ${ws_code})"
    else
        fail "WS path fallback → нет ответа (HTTP ${ws_code})"
    fi
}

test_domain() {
    section "TLS-сертификат: ${DOMAIN:-не задан}"

    local cert="${CERT_FILE:-}" key="${KEY_FILE:-}"

    if [[ ! -f "$cert" ]]; then
        fail "Сертификат не найден: ${cert:-не задан}"
        return
    fi
    ok "Файл сертификата существует: $cert"
    [[ -f "$key" ]] && ok "Файл ключа существует: $key" \
                      || fail "Файл ключа не найден: ${key:-не задан}"

    # Проверить что сертификат покрывает wildcard
    local sans
    sans=$(openssl x509 -noout -text -in "$cert" 2>/dev/null \
        | grep -A1 "Subject Alternative Name" | tail -1) || sans=""

    if echo "$sans" | grep -q "\*\.${DOMAIN:-x}"; then
        ok "Сертификат wildcard: покрывает *.${DOMAIN} (H2 субдомены OK)"
    elif [[ -n "$sans" ]]; then
        info "SAN: $sans"
        info "H2 субдомены (trh2o, vlh2o, vmh2o, ssh2o) требуют wildcard или отдельных SAN"
    fi

    local expiry
    expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2) || expiry=""
    [[ -n "$expiry" ]] && ok "Действителен до: $expiry" \
                        || fail "Не удалось прочитать срок действия"
}

test_proxy() {
    section "Проксирование через SOCKS5 127.0.0.1:${SOCKS} (VLESS+Vision+TLS)"

    if ss -tlnp "sport = :${SOCKS}" 2>/dev/null | grep -q LISTEN; then
        ok "SOCKS5 слушает :${SOCKS}"
    else
        fail "SOCKS5 НЕ слушает :${SOCKS} — запусти make client VAR=variant-c2"
        return
    fi

    local ext_ip
    ext_ip=$(curl -fsSL --max-time 10 \
        --proxy "socks5h://127.0.0.1:${SOCKS}" \
        "https://icanhazip.com" 2>/dev/null) || ext_ip=""
    [[ -n "$ext_ip" ]] \
        && ok "Внешний IP через прокси: ${ext_ip}" \
        || fail "Не удалось получить внешний IP через прокси"

    local gcode
    gcode=$(curl -fsSL --max-time 10 \
        --proxy "socks5h://127.0.0.1:${SOCKS}" \
        -o /dev/null -w "%{http_code}" \
        "https://www.google.com" 2>/dev/null) || gcode=0
    [[ "$gcode" =~ ^[1-9] ]] \
        && ok "google.com через прокси: HTTP $gcode" \
        || fail "google.com через прокси недоступен"
}

summary() {
    echo
    echo "══════════════════════════════════════"
    echo "  PASS: ${PASS}   FAIL: ${FAIL}   SKIP: ${SKIP}"
    echo "══════════════════════════════════════"
    (( FAIL == 0 )) && exit 0 || exit 1
}

case "${1:-all}" in
    server)   test_server;   summary ;;
    fallback) test_fallback; summary ;;
    domain)   test_domain;   summary ;;
    proxy)    test_proxy;    summary ;;
    all)
        test_server
        test_fallback
        test_domain
        test_proxy
        summary
        ;;
    *)
        echo "Использование: $0 {all|server|fallback|domain|proxy}"
        exit 1
        ;;
esac
