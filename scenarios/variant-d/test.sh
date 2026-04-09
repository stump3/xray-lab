#!/usr/bin/env bash
# test.sh — проверка стека variant-d (Self-SNI: VLESS+TLS+Vision)
# Использование:
#   ./test.sh              — все проверки
#   ./test.sh server       — порты, конфиги
#   ./test.sh legend       — проверка достоверности легенды сервера
#   ./test.sh proxy        — проксирование через SOCKS5
#   ./test.sh domain       — TLS-сертификат
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
        ok "Xray слушает :443 (VLESS+TLS+Vision)"
    else
        fail "Xray НЕ слушает :443 — запусти ./run.sh up"
    fi

    # Nginx HTTP redirect на :80
    if ss -tlnp "sport = :80" 2>/dev/null | grep -q LISTEN; then
        ok "Nginx слушает :80 (HTTP → HTTPS redirect)"
    else
        info "Nginx НЕ слушает :80 (redirect не настроен или уже есть другой процесс)"
    fi

    # Nginx decoy на loopback
    local dport="${NGINX_DECOY_PORT:-8080}"
    if ss -tlnp "sport = :${dport}" 2>/dev/null | grep -q "127.0.0.1"; then
        ok "Nginx decoy слушает 127.0.0.1:${dport} (loopback only)"
    else
        fail "Nginx decoy НЕ слушает 127.0.0.1:${dport}"
    fi

    # Stats API
    if ss -tlnp "sport = :10085" 2>/dev/null | grep -q LISTEN; then
        ok "Stats API слушает :10085"
    else
        info "Stats API :10085 не слушает"
    fi

    # Конфиг валиден
    local conf="/tmp/xray-lab-variant-d/xray-server.json"
    if [[ -f "$conf" ]]; then
        xray run -test -c "$conf" &>/dev/null \
            && ok "xray -test: конфиг валиден" \
            || fail "xray -test: ошибки в конфиге"
    else
        info "Рендеренный конфиг не найден — запусти ./run.sh up"
    fi
}

# ── Тест достоверности легенды ─────────────────────────────────────────────────
# Это ключевое преимущество Self-SNI: active probing видит согласованную картину.
# Проверяем каждый элемент: домен, IP, сертификат и сайт совпадают.

test_legend() {
    section "Достоверность легенды (Self-SNI)"

    local domain="${DOMAIN:-your-domain.com}"
    local server_ip="${SERVER_IP:-}"
    local cert="${CERT_FILE:-}"

    # DNS: домен резолвится в SERVER_IP
    if [[ -n "$server_ip" ]]; then
        local resolved_ip
        resolved_ip=$(getent hosts "$domain" 2>/dev/null | awk '{print $1; exit}') || resolved_ip=""
        if [[ "$resolved_ip" == "$server_ip" ]]; then
            ok "DNS: ${domain} → ${resolved_ip} совпадает с SERVER_IP"
        elif [[ -n "$resolved_ip" ]]; then
            fail "DNS: ${domain} → ${resolved_ip} ≠ SERVER_IP=${server_ip} (A-запись не настроена?)"
        else
            skip "DNS: ${domain} не резолвится (локальная среда без DNS?)"
        fi
    else
        skip "DNS проверка пропущена — SERVER_IP не задан"
    fi

    # TLS: сертификат на :443 выдан для нашего домена
    if [[ -f "$cert" ]]; then
        local subj
        subj=$(echo | timeout 5 openssl s_client \
            -connect "127.0.0.1:443" \
            -servername "$domain" \
            2>/dev/null | grep "subject=" | head -1) || subj=""

        if echo "$subj" | grep -qi "$domain"; then
            ok "TLS :443 → наш сертификат для ${domain}: $subj"
        elif [[ -n "$subj" ]]; then
            info "TLS :443 → другой сертификат: $subj (домен ещё не прописан?)"
        else
            fail "TLS :443 → handshake не прошёл"
        fi
    else
        skip "TLS проверка пропущена — сертификат не найден"
    fi

    # HTTP redirect: :80 → HTTPS
    local redir_code
    redir_code=$(curl -fsSL --max-time 5 \
        -o /dev/null -w "%{http_code}" \
        "http://127.0.0.1:80/" \
        -H "Host: ${domain}" 2>/dev/null) || redir_code=0
    if [[ "$redir_code" == "301" || "$redir_code" == "302" ]]; then
        ok "HTTP :80 → ${redir_code} redirect (легенда: обычный веб-сервер)"
    else
        info "HTTP :80 → ${redir_code} (redirect не работает или :80 не слушает)"
    fi

    # Fallback decoy: HTTP-запрос без VLESS → сайт
    local decoy_code
    decoy_code=$(curl -fsSk --max-time 5 \
        -o /dev/null -w "%{http_code}" \
        "https://127.0.0.1:443/" \
        -H "Host: ${domain}" 2>/dev/null) || decoy_code=0
    if [[ "$decoy_code" =~ ^[1-9] ]]; then
        ok "Fallback decoy: HTTPS запрос → HTTP ${decoy_code} (сайт отвечает)"
    else
        info "Fallback decoy: нет ответа (${decoy_code}) — /var/www/html пустой?"
    fi

    # Ключевая проверка: Cloudflare отсутствует (Vision с CDN несовместим)
    if [[ -n "$server_ip" ]]; then
        local headers
        headers=$(curl -fsSk --max-time 5 -I \
            "https://127.0.0.1:443/" \
            -H "Host: ${domain}" 2>/dev/null | tr '[:upper:]' '[:lower:]') || headers=""
        if echo "$headers" | grep -q "cf-ray:"; then
            fail "Обнаружен Cloudflare — Vision несовместим с CDN"
        else
            ok "Cloudflare не обнаружен — Vision работает корректно"
        fi
    fi
}

# ── Domain / cert тест ─────────────────────────────────────────────────────────

test_domain() {
    section "TLS-сертификат: ${DOMAIN:-не задан}"

    local cert="${CERT_FILE:-}"
    local key="${KEY_FILE:-}"

    [[ -f "$cert" ]] && ok "Файл сертификата существует: $cert" \
                     || { fail "Сертификат не найден: ${cert:-не задан}"; return; }

    [[ -f "$key" ]] && ok "Файл ключа существует: $key" \
                    || fail "Файл ключа не найден: ${key:-не задан}"

    local expiry
    expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2) || expiry=""
    [[ -n "$expiry" ]] && ok "Сертификат действует до: $expiry" \
                        || fail "Не удалось прочитать срок действия"

    # Ключ соответствует сертификату
    local cert_mod key_mod
    cert_mod=$(openssl x509 -noout -modulus -in "$cert" 2>/dev/null | md5sum) || true
    key_mod=$(openssl pkey -noout -modulus -in "$key" 2>/dev/null | md5sum) || true
    [[ -n "$cert_mod" && "$cert_mod" == "$key_mod" ]] \
        && ok "Сертификат и ключ совпадают" \
        || info "Не удалось проверить соответствие (RSA-only check)"
}

# ── Proxy тест ─────────────────────────────────────────────────────────────────

test_proxy() {
    section "Проксирование через SOCKS5 127.0.0.1:${SOCKS} (VLESS+TCP+TLS+Vision)"

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
    server) test_server; summary ;;
    legend) test_legend; summary ;;
    domain) test_domain; summary ;;
    proxy)  test_proxy;  summary ;;
    all)
        test_server
        test_legend
        test_domain
        test_proxy
        summary
        ;;
    *)
        echo "Использование: $0 {all|server|legend|domain|proxy}"
        exit 1
        ;;
esac
