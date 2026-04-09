#!/usr/bin/env bash
# test.sh — проверка стека variant-c (Xray native fallbacks, All-in-One)
# Использование:
#   ./test.sh              — все проверки
#   ./test.sh server       — порты, конфиги, unix socket
#   ./test.sh fallback     — проверка fallback-маршрутизации
#   ./test.sh proxy        — проксирование через SOCKS5 (VLESS+WS+TLS)
#   ./test.sh domain       — TLS-сертификат и доступность домена
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

# ── Серверные тесты ────────────────────────────────────────────────────────────

test_server() {
    section "Сервер"

    # Xray на :443
    if ss -tlnp "sport = :443" 2>/dev/null | grep -q LISTEN; then
        ok "Xray слушает :443 (VLESS+TLS главный inbound)"
    else
        fail "Xray НЕ слушает :443 — запусти ./run.sh up"
    fi

    # VLESS WS sub-inbound
    local vport="${VLESS_WS_PORT:-9001}"
    if ss -tlnp "sport = :${vport}" 2>/dev/null | grep -q LISTEN; then
        ok "VLESS WS sub-inbound слушает :${vport}"
    else
        fail "VLESS WS sub-inbound НЕ слушает :${vport}"
    fi

    # VMess WS sub-inbound
    local mport="${VMESS_WS_PORT:-9002}"
    if ss -tlnp "sport = :${mport}" 2>/dev/null | grep -q LISTEN; then
        ok "VMess WS sub-inbound слушает :${mport}"
    else
        fail "VMess WS sub-inbound НЕ слушает :${mport}"
    fi

    # Stats API
    if ss -tlnp "sport = :10085" 2>/dev/null | grep -q LISTEN; then
        ok "Stats API слушает :10085"
    else
        info "Stats API :10085 не слушает"
    fi

    # Unix socket (Nginx decoy)
    local sock="${H1_SOCK:-/dev/shm/xraylab-c-h1.sock}"
    if [[ -S "$sock" ]]; then
        ok "Nginx unix socket существует: $sock"
    else
        fail "Nginx unix socket отсутствует: $sock — Nginx не запущен?"
    fi

    # Конфиг валиден
    local conf="/tmp/xray-lab-variant-c/xray-server.json"
    if [[ -f "$conf" ]]; then
        xray run -test -c "$conf" &>/dev/null \
            && ok "xray -test: конфиг валиден" \
            || fail "xray -test: ошибки в конфиге"
    else
        info "Рендеренный конфиг не найден — запусти ./run.sh up"
    fi
}

# ── Fallback тест ──────────────────────────────────────────────────────────────

test_fallback() {
    section "Fallback маршрутизация"

    local domain="${DOMAIN:-your-domain.com}"
    local cert="${CERT_FILE:-}"

    if [[ ! -f "$cert" ]]; then
        skip "TLS-сертификат не найден — тест fallback пропущен"
        return
    fi

    # Xray на :443 должен отвечать TLS с нашим сертификатом
    local subj
    subj=$(echo | timeout 5 openssl s_client \
        -connect "127.0.0.1:443" \
        -servername "$domain" \
        2>/dev/null | grep "subject=" | head -1) || subj=""

    if echo "$subj" | grep -qi "$domain"; then
        ok "TLS :443 → наш сертификат (${domain}): $subj"
    elif [[ -n "$subj" ]]; then
        info "TLS :443 → другой сертификат: $subj"
    else
        fail "TLS :443 → handshake не прошёл"
    fi

    # Fallback на decoy: HTTP-запрос на :443 без VLESS-заголовков должен
    # вернуть HTTP-ответ от Nginx (через unix socket)
    local http_code
    http_code=$(curl -fsSk --max-time 5 \
        -o /dev/null -w "%{http_code}" \
        "https://127.0.0.1:443/" \
        -H "Host: ${domain}" 2>/dev/null) || http_code=0

    if [[ "$http_code" =~ ^[1-9] ]]; then
        ok "Fallback → Nginx decoy: HTTP ${http_code}"
    else
        info "Fallback → Nginx decoy: нет HTTP-ответа (${http_code}) — decoy статика не настроена?"
    fi

    # WS path → sub-inbound (проверяем что 101 Switching Protocols)
    local ws_path="${VLESS_WS_PATH:-/vless-ws}"
    local ws_code
    ws_code=$(curl -fsSk --max-time 5 \
        -o /dev/null -w "%{http_code}" \
        --http1.1 \
        -H "Upgrade: websocket" \
        -H "Connection: Upgrade" \
        -H "Host: ${domain}" \
        "https://127.0.0.1:443${ws_path}" 2>/dev/null) || ws_code=0

    # 101 = upgrade, 400 = xray принял но не устроил handshake без клиента (тоже OK)
    if [[ "$ws_code" == "101" || "$ws_code" == "400" ]]; then
        ok "WS path ${ws_path} → sub-inbound (HTTP ${ws_code})"
    else
        fail "WS path ${ws_path} → нет ответа sub-inbound (HTTP ${ws_code})"
    fi
}

# ── Domain / cert тест ─────────────────────────────────────────────────────────

test_domain() {
    section "TLS-сертификат: ${DOMAIN:-не задан}"

    local cert="${CERT_FILE:-}"
    local key="${KEY_FILE:-}"

    if [[ ! -f "$cert" ]]; then
        fail "Сертификат не найден: ${cert:-не задан}"
        return
    fi
    ok "Файл сертификата существует: $cert"

    [[ -f "$key" ]] && ok "Файл ключа существует: $key" \
                    || fail "Файл ключа не найден: ${key:-не задан}"

    # Срок действия
    local expiry
    expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2) || expiry=""
    [[ -n "$expiry" ]] && ok "Сертификат действует до: $expiry" \
                        || fail "Не удалось прочитать срок действия сертификата"
}

# ── Proxy тест ─────────────────────────────────────────────────────────────────

test_proxy() {
    section "Проксирование через SOCKS5 127.0.0.1:${SOCKS} (VLESS+WS+TLS)"

    if ss -tlnp "sport = :${SOCKS}" 2>/dev/null | grep -q LISTEN; then
        ok "SOCKS5 слушает :${SOCKS}"
    else
        fail "SOCKS5 НЕ слушает :${SOCKS} — запусти ./run.sh client"
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

# ── Итог ──────────────────────────────────────────────────────────────────────

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
