#!/usr/bin/env bash
# gen-link.sh — генерация subscription ссылок для variant-c2 (17 протоколов)
# Вызывается через tools/gen-link.sh variant-c2 [--qr] [--save]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

VARS="${SCRIPT_DIR}/vars.env"
[[ -f "$VARS" ]] || { echo "ERROR: $VARS не найден"; exit 1; }
set -a; source "$VARS"; set +a

for v in UUID TR_PASSWORD SS_PASSWORD DOMAIN; do
    [[ -n "${!v:-}" ]] || { echo "ERROR: $v не задан в vars.env"; exit 1; }
done

urlencode() {
    python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe='/'))" "$1"
}

vmess_link() {
    local name="$1" net="$2" path_or_svc="$3" host="${4:-$DOMAIN}"
    python3 - "$name" "$net" "$path_or_svc" "$host" << 'PYEOF'
import json, base64, sys
name, net, path_or_svc, host = sys.argv[1:]
obj = {
    "v": "2", "ps": name, "add": host, "port": "443", "id": "UUID_PLACEHOLDER",
    "aid": "0", "net": net, "type": "none", "host": host,
    "path": path_or_svc if net in ("ws","tcp","http") else "",
    "tls": "tls", "sni": host, "fp": "chrome"
}
if net == "grpc":
    obj["path"] = ""
    obj["type"] = path_or_svc  # serviceName goes here for some clients
print("vmess://" + base64.b64encode(json.dumps(obj).encode()).decode())
PYEOF
}

# Заменяем плейсхолдер UUID в vmess ссылках
vmess_link_real() {
    vmess_link "$@" | sed "s/UUID_PLACEHOLDER/${UUID}/g"
}

LINKS=()

# ── 1. VLESS + Vision + TLS ──────────────────────────────────────────────────
L="vless://${UUID}@${DOMAIN}:443"
L+="?security=tls&encryption=none&type=tcp&flow=xtls-rprx-vision"
L+="&sni=${DOMAIN}&fp=chrome#C2-01-VLESS-Vision"
LINKS+=("$L")

# ── 2. VLESS + TCP + HTTP obfs ────────────────────────────────────────────────
L="vless://${UUID}@${DOMAIN}:443"
L+="?security=tls&encryption=none&type=tcp&headerType=http"
L+="&path=$(urlencode "${VLESS_TC_PATH}")&sni=${DOMAIN}&fp=chrome#C2-02-VLESS-TCP"
LINKS+=("$L")

# ── 3. VLESS + WebSocket ──────────────────────────────────────────────────────
L="vless://${UUID}@${DOMAIN}:443"
L+="?security=tls&encryption=none&type=ws"
L+="&path=$(urlencode "${VLESS_WS_PATH}")&sni=${DOMAIN}&fp=chrome#C2-03-VLESS-WS"
LINKS+=("$L")

# ── 4. VLESS + gRPC ───────────────────────────────────────────────────────────
L="vless://${UUID}@${DOMAIN}:443"
L+="?security=tls&encryption=none&type=grpc"
L+="&serviceName=${VLESS_GRPC_SVC}&sni=${DOMAIN}&fp=chrome#C2-04-VLESS-gRPC"
LINKS+=("$L")

# ── 5. VLESS + H2 ─────────────────────────────────────────────────────────────
L="vless://${UUID}@${VLESS_H2_SNI}:443"
L+="?security=tls&encryption=none&type=http"
L+="&host=${VLESS_H2_SNI}&path=/vlh2&sni=${VLESS_H2_SNI}&fp=chrome#C2-05-VLESS-H2"
LINKS+=("$L")

# ── 6. VMess + TCP + HTTP obfs ────────────────────────────────────────────────
LINKS+=("$(vmess_link_real "C2-06-VMess-TCP" "tcp" "${VMESS_TC_PATH}")")

# ── 7. VMess + WebSocket ──────────────────────────────────────────────────────
LINKS+=("$(vmess_link_real "C2-07-VMess-WS" "ws" "${VMESS_WS_PATH}")")

# ── 8. VMess + gRPC ───────────────────────────────────────────────────────────
LINKS+=("$(vmess_link_real "C2-08-VMess-gRPC" "grpc" "${VMESS_GRPC_SVC}")")

# ── 9. VMess + H2 ─────────────────────────────────────────────────────────────
LINKS+=("$(vmess_link_real "C2-09-VMess-H2" "http" "/vmh2" "${VMESS_H2_SNI}")")

# ── 10. Trojan + TCP ──────────────────────────────────────────────────────────
L="trojan://${TR_PASSWORD}@${DOMAIN}:443"
L+="?security=tls&type=tcp&sni=${DOMAIN}&fp=chrome#C2-10-Trojan-TCP"
LINKS+=("$L")

# ── 11. Trojan + WebSocket ────────────────────────────────────────────────────
L="trojan://${TR_PASSWORD}@${DOMAIN}:443"
L+="?security=tls&type=ws&path=$(urlencode "${TROJAN_WS_PATH}")&sni=${DOMAIN}&fp=chrome#C2-11-Trojan-WS"
LINKS+=("$L")

# ── 12. Trojan + gRPC ─────────────────────────────────────────────────────────
L="trojan://${TR_PASSWORD}@${DOMAIN}:443"
L+="?security=tls&type=grpc&serviceName=${TROJAN_GRPC_SVC}&sni=${DOMAIN}&fp=chrome#C2-12-Trojan-gRPC"
LINKS+=("$L")

# ── 13. Trojan + H2 ───────────────────────────────────────────────────────────
L="trojan://${TR_PASSWORD}@${TROJAN_H2_SNI}:443"
L+="?security=tls&type=http&host=${TROJAN_H2_SNI}&path=/trh2&sni=${TROJAN_H2_SNI}&fp=chrome#C2-13-Trojan-H2"
LINKS+=("$L")

# ── 14–17. Shadowsocks — клиенты с поддержкой транспорта (v2ray-plugin / Xray) ─
# Стандартный SS URI не включает транспорт. Ссылки в формате SIP002 + plugin.
SS_B64=$(echo -n "${SS_METHOD}:${SS_PASSWORD}" | base64 -w0)

L="ss://${SS_B64}@${DOMAIN}:${SS_WS_PORT}"
L+="?plugin=v2ray-plugin%3Bmode%3Dwebsocket%3Bpath%3D$(urlencode "${SS_WS_PATH}")#C2-14-SS-WS"
LINKS+=("$L")

L="ss://${SS_B64}@${DOMAIN}:${SS_TC_PORT}"
L+="?plugin=v2ray-plugin%3Bmode%3Dhttp%3Bpath%3D$(urlencode "${SS_TC_PATH}")#C2-15-SS-TCP"
LINKS+=("$L")

L="ss://${SS_B64}@${DOMAIN}:${SS_GRPC_PORT}"
L+="?plugin=v2ray-plugin%3Bmode%3Dgrpc%3BserviceName%3D${SS_GRPC_SVC}#C2-16-SS-gRPC"
LINKS+=("$L")

L="ss://${SS_B64}@${SS_H2_SNI}:${SS_H2_PORT}"
L+="?plugin=v2ray-plugin%3Bmode%3Dhttp2%3Bhost%3D${SS_H2_SNI}#C2-17-SS-H2"
LINKS+=("$L")

# ── Вывод ────────────────────────────────────────────────────────────────────

NAMES=(
    "1.  VLESS + Vision + TLS      (главный, наивысший приоритет)"
    "2.  VLESS + TCP + HTTP obfs   + TLS"
    "3.  VLESS + WebSocket         + TLS  (CDN-совместимый)"
    "4.  VLESS + gRPC              + TLS  (CDN-совместимый)"
    "5.  VLESS + H2                + TLS  (SNI: ${VLESS_H2_SNI})"
    "6.  VMess + TCP + HTTP obfs   + TLS"
    "7.  VMess + WebSocket         + TLS  (CDN-совместимый)"
    "8.  VMess + gRPC              + TLS  (CDN-совместимый)"
    "9.  VMess + H2                + TLS  (SNI: ${VMESS_H2_SNI})"
    "10. Trojan + TCP              + TLS"
    "11. Trojan + WebSocket        + TLS  (CDN-совместимый)"
    "12. Trojan + gRPC             + TLS  (CDN-совместимый)"
    "13. Trojan + H2               + TLS  (SNI: ${TROJAN_H2_SNI})"
    "14. Shadowsocks + WebSocket         (v2ray-plugin, порт ${SS_WS_PORT})"
    "15. Shadowsocks + TCP obfs          (v2ray-plugin, порт ${SS_TC_PORT})"
    "16. Shadowsocks + gRPC              (v2ray-plugin, порт ${SS_GRPC_PORT})"
    "17. Shadowsocks + H2                (v2ray-plugin, SNI: ${SS_H2_SNI})"
)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  variant-c2 · All-in-One · 17 протоколов на :443"
echo "  Server: ${DOMAIN}:443   IP: ${SERVER_IP}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

QR=0; SAVE=0
for arg in "$@"; do
    [[ "$arg" == "--qr"   ]] && QR=1
    [[ "$arg" == "--save" ]] && SAVE=1
done

for i in "${!LINKS[@]}"; do
    echo "── ${NAMES[$i]}"
    echo "   ${LINKS[$i]}"
    if (( QR )); then
        if command -v qrencode &>/dev/null; then
            qrencode -t ANSIUTF8 "${LINKS[$i]}"
        fi
    fi
    echo
done

if (( SAVE )); then
    NOTES_DIR="${REPO_ROOT}/notes"
    mkdir -p "$NOTES_DIR"
    OUT="${NOTES_DIR}/variant-c2-links.txt"
    printf "%s\n" "${LINKS[@]}" > "$OUT"
    echo "Сохранено: $OUT"
fi
