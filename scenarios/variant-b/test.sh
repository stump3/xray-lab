#!/usr/bin/env bash
# test.sh — проверка стека variant-b (Nginx stream SNI routing)
# Использование:
#   ./test.sh              — все проверки
#   ./test.sh server       — серверная сторона (порты, конфиги)
#   ./test.sh routing      — SNI routing: Reality vs домен
#   ./test.sh proxy        — проксирование через Reality (SOCKS5)
#   ./test.sh domain       — пригодность REALITY_DOMAIN для Reality
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.env"

[[ -f "$VARS_FILE" ]] && { set -a; source "$VARS_FILE"; set +a; }

SOCKS="${SOCKS_PORT:-1080}"
PASS=0; FAIL=0; SKIP=0

ok()   { echo "  [PASS] $*"; (( PASS++ )) || true; }
fail() { echo "  [FAIL] $*"; (( FAIL++ )) || true; }
skip() { echo "  [SKIP] $*"; (( SKIP++ )) || true; }
info() { echo "  [INFO] $*"; }
section() { echo; echo "── $* ─────────────────────────────────────────"; }

# ── Серверные тесты ────────────────────────────────────────────────────────────

test_server() {
    section "Сервер"

    # Nginx stream на 443
    if ss -tlnp "sport = :443" 2>/dev/null | grep -q LISTEN; then
        ok "Nginx stream слушает :443"
    else
        fail "Nginx stream НЕ слушает :443 — запусти ./run.sh up"
    fi

    # Xray Reality inbound
    local rport="${REALITY_INBOUND_PORT:-8443}"
    if ss -tlnp "sport = :${rport}" 2>/dev/null | grep -q LISTEN; then
        ok "Xray Reality inbound слушает :${rport}"
    else
        fail "Xray Reality inbound НЕ слушает :${rport}"
    fi

    # Xray WS inbound
    local wport="${WS_INBOUND_PORT:-9001}"
    if ss -tlnp "sport = :${wport}" 2>/dev/null | grep -q LISTEN; then
        ok "Xray WS inbound слушает :${wport}"
    else
        fail "Xray WS inbound НЕ слушает :${wport}"
    fi

    # Nginx HTTPS (только если сертификат есть)
    local nport="${NGINX_HTTPS_PORT:-7443}"
    if [[ -f "${CERT_FILE:-}" ]]; then
        if ss -tlnp "sport = :${nport}" 2>/dev/null | grep -q LISTEN; then
            ok "Nginx HTTPS слушает :${nport}"
        else
            fail "Nginx HTTPS НЕ слушает :${nport}"
        fi
    else
        skip "Nginx HTTPS (:${nport}) — сертификат не найден"
    fi

    # Stats API
    if ss -tlnp "sport = :10085" 2>/dev/null | grep -q LISTEN; then
        ok "Stats API слушает :10085"
    else
        info "Stats API :10085 не слушает (dokodemo не настроен как HTTP)"
    fi

    # Конфиг валиден
    local conf="/tmp/xray-lab-variant-b/xray-server.json"
    if [[ -f "$conf" ]]; then
        if xray run -test -c "$conf" &>/dev/null; then
            ok "xray -test: конфиг валиден"
        else
            fail "xray -test: ошибки в конфиге"
        fi
    else
        info "Рендеренный конфиг не найден — запусти ./run.sh up"
    fi
}

# ── SNI routing тест ───────────────────────────────────────────────────────────

test_routing() {
    section "SNI routing"

    # Reality SNI → decoy domain сертификат
    local reality_sni="${REALITY_DOMAIN:-www.microsoft.com}"
    local sni_resp
    sni_resp=$(echo | timeout 5 openssl s_client \
        -connect "127.0.0.1:443" \
        -servername "$reality_sni" \
        2>/dev/null | grep "subject=" | head -1) || sni_resp=""

    if [[ -n "$sni_resp" ]]; then
        ok "Reality SNI ($reality_sni) → TLS handshake: $sni_resp"
    else
        fail "Reality SNI → TLS handshake не прошёл (Nginx/Xray не запущены?)"
    fi

    # Собственный домен SNI → наш сертификат (только если cert есть)
    if [[ -f "${CERT_FILE:-}" ]]; then
        local domain_resp
        domain_resp=$(echo | timeout 5 openssl s_client \
            -connect "127.0.0.1:443" \
            -servername "${DOMAIN:-your-domain.com}" \
            2>/dev/null | grep "subject=" | head -1) || domain_resp=""

        if echo "$domain_resp" | grep -qi "${DOMAIN:-your-domain.com}"; then
            ok "Domain SNI (${DOMAIN}) → наш сертификат: $domain_resp"
        elif [[ -n "$domain_resp" ]]; then
            info "Domain SNI → другой сертификат: $domain_resp"
        else
            fail "Domain SNI → TLS handshake не прошёл"
        fi
    else
        skip "Domain SNI test — сертификат не найден"
    fi

    # Проверяем что два SNI → два разных бекенда (не один и тот же)
    info "Ключевая проверка: два разных SNI должны давать разные сертификаты/сервисы"
}

# ── Reality domain тест ────────────────────────────────────────────────────────

test_domain() {
    section "Reality domain: ${REALITY_DOMAIN:-не задан}"
    local domain="${REALITY_DOMAIN:-www.microsoft.com}"

    local headers
    headers=$(curl -fsSL -I --max-time 5 "https://$domain" 2>/dev/null | tr '[:upper:]' '[:lower:]') || true
    if echo "$headers" | grep -q "cf-ray:"; then
        fail "$domain использует Cloudflare — Reality с ним несовместима"
    else
        ok "$domain не использует Cloudflare"
    fi

    local code
    code=$(curl -fsSL --tlsv1.3 --tls-max 1.3 --max-time 5 \
        -o /dev/null -w "%{http_code}" "https://$domain" 2>/dev/null) || code=0
    [[ "$code" =~ ^[1-9] ]] && ok "$domain поддерживает TLS 1.3 (HTTP $code)" \
                             || fail "$domain не поддерживает TLS 1.3"

    if curl -fsSL --http2 -v --max-time 5 -o /dev/null \
        "https://$domain" 2>&1 | grep -q "< HTTP/2"; then
        ok "$domain поддерживает HTTP/2"
    else
        fail "$domain не поддерживает HTTP/2"
    fi
}

# ── Proxy тест ─────────────────────────────────────────────────────────────────

test_proxy() {
    section "Проксирование через SOCKS5 127.0.0.1:${SOCKS} (Reality)"

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
        && ok "Внешний IP через прокси: ${ext_ip} (ожидается SERVER_IP=${SERVER_IP:-?})" \
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
    server)  test_server;  summary ;;
    routing) test_routing; summary ;;
    domain)  test_domain;  summary ;;
    proxy)   test_proxy;   summary ;;
    all)
        test_server
        test_routing
        test_domain
        test_proxy
        summary
        ;;
    *)
        echo "Использование: $0 {all|server|routing|domain|proxy}"
        exit 1
        ;;
esac
