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

vmess_link_real() {
    local name="$1" net="$2" path_or_svc="$3" host="${4:-$DOMAIN}" htype="${5:-none}" alpn_val="${6:-}"
    python3 - "$name" "$net" "$path_or_svc" "$host" "$UUID" "$htype" "$alpn_val" << 'PYEOF'
import json, base64, sys
name, net, path_or_svc, host, uuid, htype, alpn_val = sys.argv[1:]
obj = {
    "v": "2", "ps": name, "add": host, "port": "443", "id": uuid,
    "aid": "0", "net": net, "type": htype, "host": host,
    "path": path_or_svc if net in ("ws","tcp","http","xhttp") else "",
    "tls": "tls", "sni": host, "fp": "chrome"
}
if net == "grpc":
    obj["type"] = "none"
    obj["path"] = path_or_svc
if alpn_val:
    obj["alpn"] = alpn_val
print("vmess://" + base64.b64encode(json.dumps(obj).encode()).decode())
PYEOF
}

LINKS=()

# ── 1. VLESS + Vision + TLS ──────────────────────────────────────────────────
L="vless://${UUID}@${DOMAIN}:443"
L+="?security=tls&encryption=none&type=tcp&flow=xtls-rprx-vision"
L+="&sni=${DOMAIN}&fp=chrome#C2-01-VLESS-Vision"
LINKS+=("$L")

# ── 2. VLESS + TCP + HTTP obfs ────────────────────────────────────────────────
# alpn=http/1.1 обязателен: tcp-obfs несовместим с h2 (сервер предпочитает h2 по умолчанию)
L="vless://${UUID}@${DOMAIN}:443"
L+="?security=tls&encryption=none&type=tcp&headerType=http"
L+="&path=$(urlencode "${VLESS_TC_PATH}")&host=${DOMAIN}&sni=${DOMAIN}&fp=chrome&alpn=http%2F1.1#C2-02-VLESS-TCP"
LINKS+=("$L")

# ── 3. VLESS + WebSocket ──────────────────────────────────────────────────────
L="vless://${UUID}@${DOMAIN}:443"
L+="?security=tls&encryption=none&type=ws"
L+="&path=$(urlencode "${VLESS_WS_PATH}")&host=${DOMAIN}&sni=${DOMAIN}&fp=chrome#C2-03-VLESS-WS"
LINKS+=("$L")

# ── 4. VLESS + gRPC ───────────────────────────────────────────────────────────
L="vless://${UUID}@${DOMAIN}:443"
L+="?security=tls&encryption=none&type=grpc"
L+="&serviceName=${VLESS_GRPC_SVC}&sni=${DOMAIN}&fp=chrome#C2-04-VLESS-gRPC"
LINKS+=("$L")

# ── 5. VLESS + XHTTP ──────────────────────────────────────────────────────────
L="vless://${UUID}@${DOMAIN}:443"
L+="?security=tls&encryption=none&type=xhttp"
L+="&path=$(urlencode "${VLESS_XHTTP_PATH}")&host=${DOMAIN}&sni=${DOMAIN}&fp=chrome#C2-05-VLESS-XHTTP"
LINKS+=("$L")

# ── 6. VMess + TCP + HTTP obfs ────────────────────────────────────────────────
LINKS+=("$(vmess_link_real "C2-06-VMess-TCP" "tcp" "${VMESS_TC_PATH}" "${DOMAIN}" "http" "http/1.1")")

# ── 7. VMess + WebSocket ──────────────────────────────────────────────────────
LINKS+=("$(vmess_link_real "C2-07-VMess-WS" "ws" "${VMESS_WS_PATH}")")

# ── 8. VMess + gRPC ───────────────────────────────────────────────────────────
LINKS+=("$(vmess_link_real "C2-08-VMess-gRPC" "grpc" "${VMESS_GRPC_SVC}")")

# ── 9. VMess + XHTTP ──────────────────────────────────────────────────────────
LINKS+=("$(vmess_link_real "C2-09-VMess-XHTTP" "xhttp" "${VMESS_XHTTP_PATH}")")

# ── 10. Trojan + TCP ──────────────────────────────────────────────────────────
L="trojan://${TR_PASSWORD}@${DOMAIN}:443"
L+="?security=tls&type=tcp&sni=${DOMAIN}&fp=chrome#C2-10-Trojan-TCP"
LINKS+=("$L")

# ── 11. Trojan + WebSocket ────────────────────────────────────────────────────
L="trojan://${TR_PASSWORD}@${DOMAIN}:443"
L+="?security=tls&type=ws&path=$(urlencode "${TROJAN_WS_PATH}")&host=${DOMAIN}&sni=${DOMAIN}&fp=chrome#C2-11-Trojan-WS"
LINKS+=("$L")

# ── 12. Trojan + gRPC ─────────────────────────────────────────────────────────
L="trojan://${TR_PASSWORD}@${DOMAIN}:443"
L+="?security=tls&type=grpc&serviceName=${TROJAN_GRPC_SVC}&sni=${DOMAIN}&fp=chrome#C2-12-Trojan-gRPC"
LINKS+=("$L")

# ── 13. Trojan + XHTTP ────────────────────────────────────────────────────────
L="trojan://${TR_PASSWORD}@${DOMAIN}:443"
L+="?security=tls&type=xhttp&path=$(urlencode "${TROJAN_XHTTP_PATH}")&host=${DOMAIN}&sni=${DOMAIN}&fp=chrome#C2-13-Trojan-XHTTP"
LINKS+=("$L")

# ── 14–17. Shadowsocks (нативный Xray, без v2ray-plugin) ─────────────────────
# Формат: xray://<base64(json-outbound)>  — работает в v2rayN 6+ без плагинов.
# SS+WS, SS+gRPC, SS+XHTTP через :443 (fallback), SS+TCP на :4002.

xray_ss_link() {
    local name="$1"
    python3 - "$name" "$SS_METHOD" "$SS_PASSWORD" "$DOMAIN" << 'PYEOF'
import json, base64, sys
name, method, password, domain = sys.argv[1:]

def make(tag, net, extra):
    out = {
        "tag": tag,
        "protocol": "shadowsocks",
        "settings": {"servers": [{"address": domain, "port": 443,
            "method": method, "password": password}]},
        "streamSettings": {"network": net, "security": "tls",
            "tlsSettings": {"serverName": domain, "fingerprint": "chrome"}}
    }
    out["streamSettings"].update(extra)
    return out

configs = {
    "C2-14-SS-WS":    (make("ss-ws", "ws", {"wsSettings": {"path": sys.argv[5], "headers": {"Host": domain}}}),),
    "C2-16-SS-gRPC":  (make("ss-grpc", "grpc", {"grpcSettings": {"serviceName": sys.argv[6]}}),),
    "C2-17-SS-XHTTP": (make("ss-xhttp", "xhttp", {"xhttpSettings": {"path": sys.argv[7], "host": domain}}),),
}
PYEOF
}

# Для v2rayN: используем обёртку ss:// SIP002 с plugin для WS/gRPC (плагин может отсутствовать),
# ПЛЮС выдаём отдельный JSON-файл c Xray outbound конфигом для импорта.
# SS-WS (нативный Xray outbound, без плагина)
ss_json_link() {
    local name="$1" net="$2" extra_json="$3" port="${4:-443}"
    python3 - "$name" "$SS_METHOD" "$SS_PASSWORD" "$DOMAIN" "$net" "$extra_json" "$port" << 'PYEOF'
import json, base64, sys
name, method, password, domain, net, extra_json, port = sys.argv[1:]
port = int(port)
extra = json.loads(extra_json)
stream = {"network": net, "security": "tls" if port == 443 else "none",
    "tlsSettings": {"serverName": domain, "fingerprint": "chrome"}}
stream.update(extra)
config = {
    "v": "2", "ps": name, "add": domain, "port": str(port),
    "id": password, "aid": "0", "scy": method,
    "net": net, "type": "none", "host": domain,
    "tls": "tls" if port == 443 else "", "sni": domain, "fp": "chrome",
    "protocol": "shadowsocks"
}
if net == "ws":
    ws_path = extra.get("wsSettings", {}).get("path", "/")
    config["path"] = ws_path
elif net == "grpc":
    config["path"] = extra.get("grpcSettings", {}).get("serviceName", "")
elif net == "xhttp":
    config["path"] = extra.get("xhttpSettings", {}).get("path", "/")
print("ss-xray://" + base64.b64encode(json.dumps(config).encode()).decode())
PYEOF
}

SS_B64=$(echo -n "${SS_METHOD}:${SS_PASSWORD}" | base64 -w0)

# SS-WS: :443, TLS терминирует main inbound, путь матчится fallback
L="ss://${SS_B64}@${DOMAIN}:443"
L+="?plugin=v2ray-plugin%3Btls%3Bmode%3Dwebsocket%3Bpath%3D$(urlencode "${SS_WS_PATH}")%3Bhost%3D${DOMAIN}#C2-14-SS-WS"
LINKS+=("$L")

# SS-TC: собственный порт 4002, plain TCP (никакого плагина не нужно)
L="ss://${SS_B64}@${DOMAIN}:${SS_TC_PORT}#C2-15-SS-TCP"
LINKS+=("$L")

# SS-gRPC: :443 → nginx h2c → :3004
# NOTE: SS+gRPC нативно не поддерживается в v2rayN без v2ray-plugin.
# Используем VLESS-обёртку: клиент подключается как VLESS, сервер маршрутизирует через gRPC.
# Альтернатива: установить v2ray-plugin в v2rayN отдельно.
L="vless://${UUID}@${DOMAIN}:443"
L+="?security=tls&encryption=none&type=grpc&serviceName=${SS_GRPC_SVC}&sni=${DOMAIN}&fp=chrome#C2-16-SS-gRPC-via-VLESS"
LINKS+=("$L")

# SS-XHTTP: :443, TLS fallback по пути
# NOTE: используем VLESS+XHTTP вместо SS+XHTTP — нативный Xray без плагина.
L="vless://${UUID}@${DOMAIN}:443"
L+="?security=tls&encryption=none&type=xhttp&path=$(urlencode "${SS_XHTTP_PATH}")&host=${DOMAIN}&sni=${DOMAIN}&fp=chrome#C2-17-SS-XHTTP-via-VLESS"
LINKS+=("$L")

# ── Вывод ────────────────────────────────────────────────────────────────────

NAMES=(
    "1.  VLESS + Vision + TLS      (прямой, наивысшая скрытность)"
    "2.  VLESS + TCP + HTTP obfs   + TLS"
    "3.  VLESS + WebSocket         + TLS  (CDN-совместимый)"
    "4.  VLESS + gRPC              + TLS  (CDN-совместимый)"
    "5.  VLESS + XHTTP             + TLS  (CDN-совместимый)"
    "6.  VMess + TCP + HTTP obfs   + TLS"
    "7.  VMess + WebSocket         + TLS  (CDN-совместимый)"
    "8.  VMess + gRPC              + TLS  (CDN-совместимый)"
    "9.  VMess + XHTTP             + TLS  (CDN-совместимый)"
    "10. Trojan + TCP              + TLS"
    "11. Trojan + WebSocket        + TLS  (CDN-совместимый)"
    "12. Trojan + gRPC             + TLS  (CDN-совместимый)"
    "13. Trojan + XHTTP            + TLS  (CDN-совместимый)"
    "14. Shadowsocks + WebSocket         (:443 fallback, v2ray-plugin нужен для WS/gRPC/XHTTP)"
    "15. Shadowsocks + TCP plain         (порт ${SS_TC_PORT}, без плагина, нативный SS)"
    "16. Shadowsocks + gRPC              (:443 → nginx h2c, v2ray-plugin)"
    "17. Shadowsocks + XHTTP             (:443 fallback, v2ray-plugin)"
)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  variant-c2 · All-in-One · 17 протоколов на :443"
echo "  Server: ${DOMAIN}:443   IP: ${SERVER_IP}"
echo "  H2 → XHTTP (path-based, без субдоменов, без wildcard cert)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

QR=0; SAVE=0; SUB=0
for arg in "$@"; do
    [[ "$arg" == "--qr"   ]] && QR=1
    [[ "$arg" == "--save" ]] && SAVE=1
    [[ "$arg" == "--sub"  ]] && SUB=1
done

for i in "${!LINKS[@]}"; do
    echo "── ${NAMES[$i]}"
    echo "   ${LINKS[$i]}"
    if (( QR )); then
        command -v qrencode &>/dev/null && qrencode -t ANSIUTF8 "${LINKS[$i]}" || true
    fi
    echo
done

if (( SAVE )); then
    mkdir -p "${REPO_ROOT}/notes"
    OUT="${REPO_ROOT}/notes/variant-c2-links.txt"
    printf "%s\n" "${LINKS[@]}" > "$OUT"
    echo "Сохранено: $OUT"
fi

if (( SUB )); then
    SUB_DIR="/var/www/sub"
    SUB_FILE="${SUB_DIR}/c2.txt"
    local_sub="${SUB_PATH:-/sub}"
    # base64 с переносом строк для максимальной совместимости клиентов
    SUB_B64=$(printf "%s\n" "${LINKS[@]}" | base64 -w76)
    sudo mkdir -p "$SUB_DIR"
    echo "$SUB_B64" | sudo tee "$SUB_FILE" > /dev/null
    sudo chmod 644 "$SUB_FILE"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Subscription URL:"
    echo "  https://${DOMAIN}${local_sub}/c2.txt"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi
