{
  "log": {
    "access":   "/var/log/xray/access.log",
    "error":    "/var/log/xray/error.log",
    "loglevel": "warning"
  },

  "stats": {},
  "api": {
    "tag":      "api",
    "services": ["StatsService", "HandlerService", "LoggerService"]
  },
  "policy": {
    "levels": { "0": { "statsUserUplink": true, "statsUserDownlink": true } },
    "system": { "statsInboundUplink": false, "statsInboundDownlink": false }
  },

  "inbounds": [

    {
      "tag": "api", "listen": "127.0.0.1", "port": ${API_PORT},
      "protocol": "dokodemo-door", "settings": { "address": "127.0.0.1" }
    },

    {
      "tag": "vless-tls-main", "listen": "0.0.0.0", "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID}", "email": "user-vision", "level": 0, "flow": "xtls-rprx-vision" }],
        "decryption": "none",
        "fallbacks": [
          { "path": "${VLESS_WS_PATH}",    "dest": "@vless-ws",      "xver": 2 },
          { "path": "${VMESS_WS_PATH}",    "dest": "@vmess-ws",      "xver": 2 },
          { "path": "${TROJAN_WS_PATH}",   "dest": "@trojan-ws",     "xver": 2 },
          { "path": "${SS_WS_PATH}",       "dest": ${SS_WS_PORT},    "xver": 2 },

          { "alpn": "h2", "path": "${VLESS_TC_PATH}",    "dest": "@vless-tcp",     "xver": 2 },
          { "alpn": "h2", "path": "${VMESS_TC_PATH}",    "dest": "@vmess-tcp",     "xver": 2 },
          { "alpn": "h2", "path": "${SS_TC_PATH}",       "dest": ${SS_TC_PORT},    "xver": 2 },
          { "path": "${VLESS_TC_PATH}",    "dest": "@vless-tcp",     "xver": 2 },
          { "path": "${VMESS_TC_PATH}",    "dest": "@vmess-tcp",     "xver": 2 },
          { "path": "${SS_TC_PATH}",       "dest": ${SS_TC_PORT},    "xver": 2 },

          { "alpn": "h2", "path": "${VLESS_XHTTP_PATH}", "dest": "@vless-xhttp",   "xver": 2 },
          { "alpn": "h2", "path": "${VMESS_XHTTP_PATH}", "dest": "@vmess-xhttp",   "xver": 2 },
          { "alpn": "h2", "path": "${TROJAN_XHTTP_PATH}","dest": "@trojan-xhttp",  "xver": 2 },
          { "alpn": "h2", "path": "${SS_XHTTP_PATH}",    "dest": ${SS_XHTTP_PORT}, "xver": 2 },
          { "path": "${VLESS_XHTTP_PATH}", "dest": "@vless-xhttp",   "xver": 2 },
          { "path": "${VMESS_XHTTP_PATH}", "dest": "@vmess-xhttp",   "xver": 2 },
          { "path": "${TROJAN_XHTTP_PATH}","dest": "@trojan-xhttp",  "xver": 2 },
          { "path": "${SS_XHTTP_PATH}",    "dest": ${SS_XHTTP_PORT}, "xver": 2 },

          { "alpn": "h2",                  "dest": "@trojan-tcp",    "xver": 2 },
          { "dest": "${H1_SOCK}",                                     "xver": 2 }
        ]
      },
      "streamSettings": {
        "network": "tcp", "security": "tls",
        "tlsSettings": {
          "certificates": [{ "certificateFile": "${CERT_FILE}", "keyFile": "${KEY_FILE}" }],
          "alpn": ["h2", "http/1.1"],
          "fingerprint": "chrome"
        }
      }
    },

    {
      "tag": "vless-ws", "listen": "@vless-ws", "protocol": "vless",
      "settings": { "clients": [{ "id": "${UUID}", "email": "user-vless-ws", "level": 0 }], "decryption": "none" },
      "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "${VLESS_WS_PATH}", "acceptProxyProtocol": true } },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
    },

    {
      "tag": "vmess-ws", "listen": "@vmess-ws", "protocol": "vmess",
      "settings": { "clients": [{ "id": "${UUID}", "email": "user-vmess-ws", "level": 0 }] },
      "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "${VMESS_WS_PATH}", "acceptProxyProtocol": true } },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
    },

    {
      "tag": "trojan-ws", "listen": "@trojan-ws", "protocol": "trojan",
      "settings": { "clients": [{ "password": "${TR_PASSWORD}", "email": "user-trojan-ws", "level": 0 }] },
      "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "${TROJAN_WS_PATH}", "acceptProxyProtocol": true } },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
    },

    {
      "tag": "vless-tcp", "listen": "@vless-tcp", "protocol": "vless",
      "settings": { "clients": [{ "id": "${UUID}", "email": "user-vless-tcp", "level": 0 }], "decryption": "none" },
      "streamSettings": { "network": "tcp", "security": "none", "tcpSettings": { "acceptProxyProtocol": true, "header": { "type": "http", "request": { "path": ["${VLESS_TC_PATH}"] } } } },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
    },

    {
      "tag": "vmess-tcp", "listen": "@vmess-tcp", "protocol": "vmess",
      "settings": { "clients": [{ "id": "${UUID}", "email": "user-vmess-tcp", "level": 0 }] },
      "streamSettings": { "network": "tcp", "security": "none", "tcpSettings": { "acceptProxyProtocol": true, "header": { "type": "http", "request": { "path": ["${VMESS_TC_PATH}"] } } } },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
    },

    {
      "tag": "vless-xhttp", "listen": "@vless-xhttp", "protocol": "vless",
      "settings": { "clients": [{ "id": "${UUID}", "email": "user-vless-xhttp", "level": 0 }], "decryption": "none" },
      "streamSettings": { "network": "xhttp", "security": "none", "xhttpSettings": { "path": "${VLESS_XHTTP_PATH}", "mode": "stream-one", "acceptProxyProtocol": true } },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
    },

    {
      "tag": "vmess-xhttp", "listen": "@vmess-xhttp", "protocol": "vmess",
      "settings": { "clients": [{ "id": "${UUID}", "email": "user-vmess-xhttp", "level": 0 }] },
      "streamSettings": { "network": "xhttp", "security": "none", "xhttpSettings": { "path": "${VMESS_XHTTP_PATH}", "mode": "stream-one", "acceptProxyProtocol": true } },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
    },

    {
      "tag": "trojan-xhttp", "listen": "@trojan-xhttp", "protocol": "trojan",
      "settings": { "clients": [{ "password": "${TR_PASSWORD}", "email": "user-trojan-xhttp", "level": 0 }] },
      "streamSettings": { "network": "xhttp", "security": "none", "xhttpSettings": { "path": "${TROJAN_XHTTP_PATH}", "mode": "stream-one", "acceptProxyProtocol": true } },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
    },

    {
      "tag": "trojan-tcp", "listen": "@trojan-tcp", "protocol": "trojan",
      "settings": {
        "clients": [{ "password": "${TR_PASSWORD}", "email": "user-trojan-tcp", "level": 0 }],
        "fallbacks": [{ "dest": "${H2C_SOCK}", "xver": 2 }]
      },
      "streamSettings": { "network": "tcp", "security": "none", "tcpSettings": { "acceptProxyProtocol": true } }
    },

    {
      "tag": "ss-ws", "listen": "127.0.0.1", "port": ${SS_WS_PORT}, "protocol": "shadowsocks",
      "settings": { "method": "${SS_METHOD}", "password": "${SS_PASSWORD}", "network": "tcp" },
      "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "${SS_WS_PATH}", "acceptProxyProtocol": true } }
    },

    {
      "tag": "ss-tcp", "listen": "0.0.0.0", "port": ${SS_TC_PORT}, "protocol": "shadowsocks",
      "settings": { "method": "${SS_METHOD}", "password": "${SS_PASSWORD}", "network": "tcp" },
      "streamSettings": { "network": "tcp", "security": "none", "tcpSettings": { "acceptProxyProtocol": true, "header": { "type": "http", "request": { "path": ["${SS_TC_PATH}"] } } } }
    },

    {
      "tag": "ss-xhttp", "listen": "127.0.0.1", "port": ${SS_XHTTP_PORT}, "protocol": "shadowsocks",
      "settings": { "method": "${SS_METHOD}", "password": "${SS_PASSWORD}", "network": "tcp" },
      "streamSettings": { "network": "xhttp", "security": "none", "xhttpSettings": { "path": "${SS_XHTTP_PATH}", "mode": "stream-one", "acceptProxyProtocol": true } }
    },

    {
      "tag": "trojan-grpc", "listen": "127.0.0.1", "port": ${TROJAN_GRPC_PORT}, "protocol": "trojan",
      "settings": { "clients": [{ "password": "${TR_PASSWORD}", "email": "user-trojan-grpc", "level": 0 }] },
      "streamSettings": { "network": "grpc", "security": "none", "grpcSettings": { "serviceName": "${TROJAN_GRPC_SVC}" } }
    },

    {
      "tag": "vless-grpc", "listen": "127.0.0.1", "port": ${VLESS_GRPC_PORT}, "protocol": "vless",
      "settings": { "clients": [{ "id": "${UUID}", "email": "user-vless-grpc", "level": 0 }], "decryption": "none" },
      "streamSettings": { "network": "grpc", "security": "none", "grpcSettings": { "serviceName": "${VLESS_GRPC_SVC}" } }
    },

    {
      "tag": "vmess-grpc", "listen": "127.0.0.1", "port": ${VMESS_GRPC_PORT}, "protocol": "vmess",
      "settings": { "clients": [{ "id": "${UUID}", "email": "user-vmess-grpc", "level": 0 }] },
      "streamSettings": { "network": "grpc", "security": "none", "grpcSettings": { "serviceName": "${VMESS_GRPC_SVC}" } }
    },

    {
      "tag": "ss-grpc", "listen": "127.0.0.1", "port": ${SS_GRPC_PORT}, "protocol": "shadowsocks",
      "settings": { "method": "${SS_METHOD}", "password": "${SS_PASSWORD}", "network": "tcp" },
      "streamSettings": { "network": "grpc", "security": "none", "grpcSettings": { "serviceName": "${SS_GRPC_SVC}" } }
    }

  ],

  "outbounds": [
    { "protocol": "freedom",   "tag": "direct" },
    { "protocol": "blackhole", "tag": "block"  }
  ],

  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "inboundTag": ["api"], "outboundTag": "api" },
      { "type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "block" },
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "direct" }
    ]
  }
}
