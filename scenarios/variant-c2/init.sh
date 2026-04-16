#!/usr/bin/env bash
# init.sh — инициализация vars.env для variant-c2 (All-in-One, 17 протоколов)
# Использование:
#   bash scenarios/variant-c2/init.sh           — интерактивно
#   bash scenarios/variant-c2/init.sh --auto    — без вопросов (все дефолты)
set -euo pipefail

AUTO=0
[[ "${1:-}" == "--auto" ]] && AUTO=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${SCRIPT_DIR}/vars.env"

bold()  { echo -e "\033[1m$*\033[0m" > /dev/tty; }
ok()    { echo -e "  \033[32m[✓]\033[0m $*" > /dev/tty; }
info()  { echo -e "  \033[34m[·]\033[0m $*" > /dev/tty; }
warn()  { echo -e "  \033[33m[!]\033[0m $*" > /dev/tty; }

ask() {
    local label="$1" default="$2" value
    [[ -n "$default" ]] \
        && printf "  %-34s [%s]: " "$label" "$default" > /dev/tty \
        || printf "  %-34s : " "$label" > /dev/tty
    read -r value < /dev/tty
    echo "${value:-$default}"
}

detect_ip() {
    local ip=""
    for s in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
        ip="$(curl -fsSL --max-time 3 "$s" 2>/dev/null | tr -d '[:space:]')" && break
    done
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo "$ip" || echo ""
}

gen_path() { echo "/$(openssl rand -hex 8)"; }

write_vars() {
    local domain="$1" server_ip="$2"
    local vless_ws="$3"   vmess_ws="$4"   trojan_ws="$5"   ss_ws="$6"
    local vless_tc="$7"   vmess_tc="$8"   ss_tc="$9"
    local vless_xh="${10}" vmess_xh="${11}" trojan_xh="${12}" ss_xh="${13}"
    local socks_port="${14}" http_port="${15}"

cat > "$VARS_FILE" << EOF
# Сгенерировано init.sh $(date '+%Y-%m-%d %H:%M:%S')
# wildcard-сертификат НЕ нужен — H2 заменён на XHTTP (path-based, без субдоменов)

# --- Секреты (make keys VAR=variant-c2) ---
UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
TR_PASSWORD=your-trojan-password
SS_PASSWORD=your-ss-password-base64
SS_METHOD=2022-blake3-aes-128-gcm

# --- Домен и IP ---
DOMAIN=${domain}
SERVER_IP=${server_ip}

# --- TLS сертификат (обычный, не wildcard) ---
# certbot certonly --standalone -d ${domain}
CERT_FILE=/etc/letsencrypt/live/${domain}/fullchain.pem
KEY_FILE=/etc/letsencrypt/live/${domain}/privkey.pem

# --- Пути WebSocket ---
VLESS_WS_PATH=${vless_ws}
VMESS_WS_PATH=${vmess_ws}
TROJAN_WS_PATH=${trojan_ws}
SS_WS_PATH=${ss_ws}

# --- Пути TCP HTTP-obfs ---
VLESS_TC_PATH=${vless_tc}
VMESS_TC_PATH=${vmess_tc}
SS_TC_PATH=${ss_tc}

# --- Пути XHTTP (заменяют H2 — субдомены не нужны) ---
VLESS_XHTTP_PATH=${vless_xh}
VMESS_XHTTP_PATH=${vmess_xh}
TROJAN_XHTTP_PATH=${trojan_xh}
SS_XHTTP_PATH=${ss_xh}

# --- gRPC service names ---
TROJAN_GRPC_SVC=trgrpc
VLESS_GRPC_SVC=vlgrpc
VMESS_GRPC_SVC=vmgrpc
SS_GRPC_SVC=ssgrpc

# --- Внутренние порты sub-inbounds ---
TROJAN_GRPC_PORT=3001
VLESS_GRPC_PORT=3002
VMESS_GRPC_PORT=3003
SS_GRPC_PORT=3004
SS_WS_PORT=4001
SS_TC_PORT=4002
SS_XHTTP_PORT=4003

# --- Unix sockets (Nginx) ---
H1_SOCK=/dev/shm/xraylab-c2-h1.sock
H2C_SOCK=/dev/shm/xraylab-c2-h2c.sock

# --- API ---
API_PORT=62789

# --- Subscription ---
SUB_PATH=/sub

# --- Клиент ---
SOCKS_PORT=${socks_port}
HTTP_PORT=${http_port}
EOF
}

main() {
    echo > /dev/tty
    bold "  xray-lab · variant-c2 · All-in-One (17 протоколов)"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" > /dev/tty
    echo > /dev/tty
    info "Архитектура: VLESS+Vision+TLS :443 → fallbacks → 17 протоколов + Nginx (unix sockets)"
    warn "Reality в этой схеме НЕДОСТУПНА."
    info "Обычный TLS-сертификат — wildcard НЕ нужен (H2 заменён на XHTTP)."
    echo > /dev/tty

    if (( AUTO )); then
        info "Режим --auto: дефолтные значения"
        [[ -f "$VARS_FILE" ]] && warn "vars.env уже существует — перезапись"
        SERVER_IP="$(detect_ip)"
        [[ -n "$SERVER_IP" ]] || { echo "[✗] Нет SERVER_IP" > /dev/tty; exit 1; }
        ok "SERVER_IP: ${SERVER_IP}"
        write_vars "your-domain.com" "$SERVER_IP" \
            "$(gen_path)" "$(gen_path)" "$(gen_path)" "$(gen_path)" \
            "$(gen_path)" "$(gen_path)" "$(gen_path)" \
            "$(gen_path)" "$(gen_path)" "$(gen_path)" "$(gen_path)" \
            "1080" "8118"
    else
        [[ -f "$VARS_FILE" ]] && {
            warn "vars.env уже существует"
            printf "  Продолжить? [y/N]: " > /dev/tty
            read -r c < /dev/tty; [[ "${c,,}" == "y" ]] || exit 0
        }

        echo > /dev/tty
        SERVER_IP="$(detect_ip)"
        [[ -n "$SERVER_IP" ]] && ok "Обнаружен IP: $SERVER_IP" || warn "IP не определён"
        SERVER_IP="$(ask "SERVER_IP" "$SERVER_IP")"
        [[ -n "$SERVER_IP" ]] || { echo "[✗] SERVER_IP обязателен" > /dev/tty; exit 1; }

        echo > /dev/tty
        info "Собственный домен — нужна A-запись → ${SERVER_IP}."
        info "Обычный сертификат: certbot certonly --standalone -d DOMAIN"
        DOMAIN="$(ask "DOMAIN" "your-domain.com")"

        echo > /dev/tty
        bold "  Пути WebSocket (Enter = автогенерация):"
        VLESS_WS_PATH="$(ask  "VLESS_WS_PATH"   "$(gen_path)")"
        VMESS_WS_PATH="$(ask  "VMESS_WS_PATH"   "$(gen_path)")"
        TROJAN_WS_PATH="$(ask "TROJAN_WS_PATH"  "$(gen_path)")"
        SS_WS_PATH="$(ask     "SS_WS_PATH"      "$(gen_path)")"

        echo > /dev/tty
        bold "  Пути TCP obfs (Enter = автогенерация):"
        VLESS_TC_PATH="$(ask  "VLESS_TC_PATH"   "$(gen_path)")"
        VMESS_TC_PATH="$(ask  "VMESS_TC_PATH"   "$(gen_path)")"
        SS_TC_PATH="$(ask     "SS_TC_PATH"      "$(gen_path)")"

        echo > /dev/tty
        bold "  Пути XHTTP (заменяют H2, Enter = автогенерация):"
        VLESS_XHTTP_PATH="$(ask  "VLESS_XHTTP_PATH"   "$(gen_path)")"
        VMESS_XHTTP_PATH="$(ask  "VMESS_XHTTP_PATH"   "$(gen_path)")"
        TROJAN_XHTTP_PATH="$(ask "TROJAN_XHTTP_PATH"  "$(gen_path)")"
        SS_XHTTP_PATH="$(ask     "SS_XHTTP_PATH"      "$(gen_path)")"

        echo > /dev/tty
        bold "  Клиентские порты (Enter = дефолт):"
        SOCKS_PORT="$(ask "SOCKS_PORT" "1080")"
        HTTP_PORT="$(ask  "HTTP_PORT"  "8118")"
        echo > /dev/tty

        write_vars "$DOMAIN" "$SERVER_IP" \
            "$VLESS_WS_PATH"  "$VMESS_WS_PATH"  "$TROJAN_WS_PATH" "$SS_WS_PATH" \
            "$VLESS_TC_PATH"  "$VMESS_TC_PATH"  "$SS_TC_PATH" \
            "$VLESS_XHTTP_PATH" "$VMESS_XHTTP_PATH" "$TROJAN_XHTTP_PATH" "$SS_XHTTP_PATH" \
            "$SOCKS_PORT" "$HTTP_PORT"
    fi

    ok "Записано: ${VARS_FILE}"
    echo > /dev/tty

    if (( ! AUTO )); then
        if [[ "${XRAY_QUICKSTART:-0}" == "1" ]]; then
            echo "  ↓ quickstart продолжает: keys → certbot → up → QR" > /dev/tty
        else
            bold "  Следующие шаги:"
            echo "    make keys VAR=variant-c2       ← UUID, TR_PASSWORD, SS_PASSWORD" > /dev/tty
            echo "    certbot certonly -d \$DOMAIN    ← обычный cert (не wildcard)" > /dev/tty
            echo "    make up VAR=variant-c2          ← запустить стек" > /dev/tty
            echo "    make link-qr VAR=variant-c2     ← все 17 ссылок" > /dev/tty
        fi
        echo > /dev/tty
    fi
}

main
