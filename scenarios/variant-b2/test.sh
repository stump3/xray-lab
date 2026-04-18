#!/usr/bin/env bash
# test.sh — проверка стека variant-b2
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

test_server() {
    section "Сервер: порты"

    # Nginx TCP:443
    ss -tlnp "sport = :443" 2>/dev/null | grep -q LISTEN \
        && ok "Nginx слушает TCP:443 (stream)" \
        || fail "TCP:443 не слушает — Nginx не запущен?"

    # Xray UDP:443 (Hysteria2)
    ss -ulnp 2>/dev/null | grep -q ':443' \
        && ok "Xray слушает UDP:443 (Hysteria2)" \
        || fail "UDP:443 не слушает — Hysteria2 не запущен?"

    # Reality inbound
    local rport="${REALITY_INBOUND_PORT:-8443}"
    ss -tlnp "sport = :${rport}" 2>/dev/null | grep -q LISTEN \
        && ok "Reality inbound слушает :${rport}" \
        || fail "Reality inbound не слушает :${rport}"

    # WS inbound
    local wport="${WS_INBOUND_PORT:-9001}"
    ss -tlnp "sport = :${wport}" 2>/dev/null | grep -q LISTEN \
        && ok "WS inbound слушает :${wport}" \
        || fail "WS inbound не слушает :${wport}"

    # Конфиг
    local conf="/tmp/xray-lab-variant-b2/xray-server.json"
    if [[ -f "$conf" ]]; then
        xray run -test -c "$conf" &>/dev/null \
            && ok "xray -test: конфиг валиден" \
            || fail "xray -test: ошибки в конфиге"
    else
        info "Рендеренный конфиг не найден — запусти make up VAR=variant-b2"
    fi
}

test_routing() {
    section "SNI routing"

    local domain="${DOMAIN:-your-domain.com}"
    local reality="${REALITY_DOMAIN:-www.microsoft.com}"

    # SNI = DOMAIN → должен вернуть наш сертификат
    local our_subj
    our_subj=$(echo | timeout 5 openssl s_client \
        -connect "127.0.0.1:443" -servername "$domain" \
        2>/dev/null | grep "subject=" | head -1) || our_subj=""
    echo "$our_subj" | grep -qi "$domain" \
        && ok "SNI=${domain} → наш сертификат" \
        || info "SNI=${domain} → ${our_subj:-нет ответа}"

    # SNI = REALITY_DOMAIN → должен вернуть сертификат decoy
    local decoy_subj
    decoy_subj=$(echo | timeout 5 openssl s_client \
        -connect "127.0.0.1:443" -servername "$reality" \
        2>/dev/null | grep "subject=" | head -1) || decoy_subj=""
    echo "$decoy_subj" | grep -qi "$reality" \
        && ok "SNI=${reality} → decoy сертификат (Reality)" \
        || info "SNI=${reality} → ${decoy_subj:-нет ответа}"
}

test_domain() {
    section "TLS сертификаты"

    local cert="${CERT_FILE:-}" key="${KEY_FILE:-}"
    if [[ -f "$cert" ]]; then
        ok "Сертификат Nginx: $cert"
        local exp; exp=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2) || exp=""
        [[ -n "$exp" ]] && ok "Действителен до: $exp"
    else
        fail "Сертификат Nginx не найден: ${cert:-не задан}"
    fi

    local h2cert="${H2_CERT_FILE:-}"
    if [[ "$h2cert" == "$cert" ]]; then
        ok "Hysteria2 использует тот же сертификат"
    elif [[ -f "$h2cert" ]]; then
        ok "Сертификат Hysteria2: $h2cert"
    else
        fail "Сертификат Hysteria2 не найден: ${h2cert:-не задан}"
    fi
}

test_proxy() {
    section "Проксирование через SOCKS5 :${SOCKS} (Reality)"

    ss -tlnp "sport = :${SOCKS}" 2>/dev/null | grep -q LISTEN \
        || { fail "SOCKS5 не слушает :${SOCKS} — запусти make client VAR=variant-b2"; return; }
    ok "SOCKS5 слушает :${SOCKS}"

    local ext_ip
    ext_ip=$(curl -fsSL --max-time 10 \
        --proxy "socks5h://127.0.0.1:${SOCKS}" \
        "https://icanhazip.com" 2>/dev/null) || ext_ip=""
    [[ -n "$ext_ip" ]] \
        && ok "Внешний IP через прокси: ${ext_ip}" \
        || fail "Не удалось получить внешний IP"
}

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
    *) echo "Использование: $0 {all|server|routing|domain|proxy}"; exit 1 ;;
esac
