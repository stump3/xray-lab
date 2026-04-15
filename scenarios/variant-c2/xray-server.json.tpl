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
    "levels": {
      "0": { "statsUserUplink": true, "statsUserDownlink": true }
    },
    "system": {
      "statsInboundUplink":   false,
      "statsInboundDownlink": false
    }
  },

  "inbounds": [

    // ── API ──────────────────────────────────────────────────────────────────
    {
      "tag":      "api",
      "listen":   "127.0.0.1",
      "port":     ${API_PORT},
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" }
    },

    // ── Главный inbound: VLESS+TCP+TLS+Vision на :443 ────────────────────────
    // После TLS-терминации маршрутизирует по SNI+ALPN, path, alpn, default.
    // Порядок fallbacks ВАЖЕН — SNI-specific H2 должны быть до generic alpn=h2.
    {
      "tag":      "vless-tls-main",
      "listen":   "0.0.0.0",
      "port":     443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id":    "${UUID}",
            "email": "user-vision",
            "level": 0,
            "flow":  "xtls-rprx-vision"
          }
        ],
        "decryption": "none",
        "fallbacks": [

          // 1. SNI-specific H2 — ДОЛЖНЫ быть до generic alpn=h2
          //    H2 транспорт не поддерживает PROXY protocol → xver не указываем
          { "name": "${TROJAN_H2_SNI}", "alpn": "h2", "dest": "@trojan-h2" },
          { "name": "${VLESS_H2_SNI}",  "alpn": "h2", "dest": "@vless-h2"  },
          { "name": "${VMESS_H2_SNI}",  "alpn": "h2", "dest": "@vmess-h2"  },
          { "name": "${SS_H2_SNI}",     "alpn": "h2", "dest": ${SS_H2_PORT} },

          // 2. Path-based — WebSocket + TCP obfs
          { "path": "${VLESS_WS_PATH}",   "dest": "@vless-ws",        "xver": 2 },
          { "path": "${VMESS_WS_PATH}",   "dest": "@vmess-ws",        "xver": 2 },
          { "path": "${TROJAN_WS_PATH}",  "dest": "@trojan-ws",       "xver": 2 },
          { "path": "${SS_WS_PATH}",      "dest": ${SS_WS_PORT},      "xver": 2 },
          { "path": "${VLESS_TC_PATH}",   "dest": "@vless-tcp",       "xver": 2 },
          { "path": "${VMESS_TC_PATH}",   "dest": "@vmess-tcp",       "xver": 2 },
          { "path": "${SS_TC_PATH}",      "dest": ${SS_TC_PORT},      "xver": 2 },

          // 3. Generic alpn=h2 → @trojan-tcp
          //    Trojan+TCP приземляется здесь. gRPC тоже (ALPN=h2) — провалится
          //    через fallback @trojan-tcp → h2c.sock → Nginx → grpc_pass.
          { "alpn": "h2", "dest": "@trojan-tcp", "xver": 2 },

          // 4. Default → Nginx HTTP/1.1 decoy сайт
          { "dest": "${H1_SOCK}", "xver": 2 }
        ]
      },
      "streamSettings": {
        "network":  "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${CERT_FILE}",
              "keyFile":         "${KEY_FILE}"
            }
          ],
          "alpn":        ["h2", "http/1.1"],
          "fingerprint": "chrome"
        }
      }
    },

    // ── VLESS WebSocket ───────────────────────────────────────────────────────
    {
      "tag":      "vless-ws",
      "listen":   "@vless-ws",
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID}", "email": "user-vless-ws", "level": 0 }],
        "decryption": "none"
      },
      "streamSettings": {
        "network":    "ws",
        "security":   "none",
        "wsSettings": {
          "path":               "${VLESS_WS_PATH}",
          "acceptProxyProtocol": true
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
    },

    // ── VMess WebSocket ───────────────────────────────────────────────────────
    {
      "tag":      "vmess-ws",
      "listen":   "@vmess-ws",
      "protocol": "vmess",
      "settings": {
        "clients": [{ "id": "${UUID}", "email": "user-vmess-ws", "level": 0 }]
      },
      "streamSettings": {
        "network":    "ws",
        "security":   "none",
        "wsSettings": {
          "path":               "${VMESS_WS_PATH}",
          "acceptProxyProtocol": true
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
    },

    // ── Trojan WebSocket ──────────────────────────────────────────────────────
    {
      "tag":      "trojan-ws",
      "listen":   "@trojan-ws",
      "protocol": "trojan",
      "settings": {
        "clients": [{ "password": "${TR_PASSWORD}", "email": "user-trojan-ws", "level": 0 }]
      },
      "streamSettings": {
        "network":    "ws",
        "security":   "none",
        "wsSettings": {
          "path":               "${TROJAN_WS_PATH}",
          "acceptProxyProtocol": true
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
    },

    // ── VLESS TCP + HTTP obfs ─────────────────────────────────────────────────
    {
      "tag":      "vless-tcp",
      "listen":   "@vless-tcp",
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID}", "email": "user-vless-tcp", "level": 0 }],
        "decryption": "none"
      },
      "streamSettings": {
        "network":  "tcp",
        "security": "none",
        "tcpSettings": {
          "acceptProxyProtocol": true,
          "header": {
            "type": "http",
            "request": { "path": ["${VLESS_TC_PATH}"] }
          }
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
    },

    // ── VMess TCP + HTTP obfs ─────────────────────────────────────────────────
    {
      "tag":      "vmess-tcp",
      "listen":   "@vmess-tcp",
      "protocol": "vmess",
      "settings": {
        "clients": [{ "id": "${UUID}", "email": "user-vmess-tcp", "level": 0 }]
      },
      "streamSettings": {
        "network":  "tcp",
        "security": "none",
        "tcpSettings": {
          "acceptProxyProtocol": true,
          "header": {
            "type": "http",
            "request": { "path": ["${VMESS_TC_PATH}"] }
          }
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
    },

    // ── Trojan TCP (alpn=h2 generic) ─────────────────────────────────────────
    // Принимает Trojan+TCP и gRPC. Валидный Trojan → proxied.
    // Невалидный (gRPC) → второй fallback → h2c.sock → Nginx → grpc_pass.
    {
      "tag":      "trojan-tcp",
      "listen":   "@trojan-tcp",
      "protocol": "trojan",
      "settings": {
        "clients": [{ "password": "${TR_PASSWORD}", "email": "user-trojan-tcp", "level": 0 }],
        "fallbacks": [
          { "dest": "${H2C_SOCK}", "xver": 2 }
        ]
      },
      "streamSettings": {
        "network":  "tcp",
        "security": "none",
        "tcpSettings": { "acceptProxyProtocol": true }
      }
    },

    // ── VLESS H2 (SNI: vlh2o.DOMAIN) ─────────────────────────────────────────
    {
      "tag":      "vless-h2",
      "listen":   "@vless-h2",
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID}", "email": "user-vless-h2", "level": 0 }],
        "decryption": "none"
      },
      "streamSettings": {
        "network":      "h2",
        "security":     "none",
        "httpSettings": {
          "path": "/vlh2",
          "host": ["${VLESS_H2_SNI}"]
        }
      }
    },

    // ── VMess H2 (SNI: vmh2o.DOMAIN) ─────────────────────────────────────────
    {
      "tag":      "vmess-h2",
      "listen":   "@vmess-h2",
      "protocol": "vmess",
      "settings": {
        "clients": [{ "id": "${UUID}", "email": "user-vmess-h2", "level": 0 }]
      },
      "streamSettings": {
        "network":      "h2",
        "security":     "none",
        "httpSettings": {
          "path": "/vmh2",
          "host": ["${VMESS_H2_SNI}"]
        }
      }
    },

    // ── Trojan H2 (SNI: trh2o.DOMAIN) ────────────────────────────────────────
    {
      "tag":      "trojan-h2",
      "listen":   "@trojan-h2",
      "protocol": "trojan",
      "settings": {
        "clients": [{ "password": "${TR_PASSWORD}", "email": "user-trojan-h2", "level": 0 }]
      },
      "streamSettings": {
        "network":      "h2",
        "security":     "none",
        "httpSettings": {
          "path": "/trh2",
          "host": ["${TROJAN_H2_SNI}"]
        }
      }
    },

    // ── Shadowsocks WebSocket ─────────────────────────────────────────────────
    {
      "tag":      "ss-ws",
      "listen":   "127.0.0.1",
      "port":     ${SS_WS_PORT},
      "protocol": "shadowsocks",
      "settings": {
        "method":   "${SS_METHOD}",
        "password": "${SS_PASSWORD}",
        "network":  "tcp"
      },
      "streamSettings": {
        "network":    "ws",
        "security":   "none",
        "wsSettings": {
          "path":               "${SS_WS_PATH}",
          "acceptProxyProtocol": true
        }
      }
    },

    // ── Shadowsocks TCP + HTTP obfs ───────────────────────────────────────────
    {
      "tag":      "ss-tcp",
      "listen":   "127.0.0.1",
      "port":     ${SS_TC_PORT},
      "protocol": "shadowsocks",
      "settings": {
        "method":   "${SS_METHOD}",
        "password": "${SS_PASSWORD}",
        "network":  "tcp"
      },
      "streamSettings": {
        "network":  "tcp",
        "security": "none",
        "tcpSettings": {
          "acceptProxyProtocol": true,
          "header": {
            "type": "http",
            "request": { "path": ["${SS_TC_PATH}"] }
          }
        }
      }
    },

    // ── Shadowsocks H2 (SNI: ssh2o.DOMAIN) ───────────────────────────────────
    {
      "tag":      "ss-h2",
      "listen":   "127.0.0.1",
      "port":     ${SS_H2_PORT},
      "protocol": "shadowsocks",
      "settings": {
        "method":   "${SS_METHOD}",
        "password": "${SS_PASSWORD}",
        "network":  "tcp"
      },
      "streamSettings": {
        "network":      "h2",
        "security":     "none",
        "httpSettings": {
          "path": "/ssh2",
          "host": ["${SS_H2_SNI}"]
        }
      }
    },

    // ── Trojan gRPC (via Nginx h2c.sock → grpc_pass) ─────────────────────────
    {
      "tag":      "trojan-grpc",
      "listen":   "127.0.0.1",
      "port":     ${TROJAN_GRPC_PORT},
      "protocol": "trojan",
      "settings": {
        "clients": [{ "password": "${TR_PASSWORD}", "email": "user-trojan-grpc", "level": 0 }]
      },
      "streamSettings": {
        "network":      "grpc",
        "security":     "none",
        "grpcSettings": { "serviceName": "${TROJAN_GRPC_SVC}" }
      }
    },

    // ── VLESS gRPC ────────────────────────────────────────────────────────────
    {
      "tag":      "vless-grpc",
      "listen":   "127.0.0.1",
      "port":     ${VLESS_GRPC_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID}", "email": "user-vless-grpc", "level": 0 }],
        "decryption": "none"
      },
      "streamSettings": {
        "network":      "grpc",
        "security":     "none",
        "grpcSettings": { "serviceName": "${VLESS_GRPC_SVC}" }
      }
    },

    // ── VMess gRPC ────────────────────────────────────────────────────────────
    {
      "tag":      "vmess-grpc",
      "listen":   "127.0.0.1",
      "port":     ${VMESS_GRPC_PORT},
      "protocol": "vmess",
      "settings": {
        "clients": [{ "id": "${UUID}", "email": "user-vmess-grpc", "level": 0 }]
      },
      "streamSettings": {
        "network":      "grpc",
        "security":     "none",
        "grpcSettings": { "serviceName": "${VMESS_GRPC_SVC}" }
      }
    },

    // ── Shadowsocks gRPC ──────────────────────────────────────────────────────
    {
      "tag":      "ss-grpc",
      "listen":   "127.0.0.1",
      "port":     ${SS_GRPC_PORT},
      "protocol": "shadowsocks",
      "settings": {
        "method":   "${SS_METHOD}",
        "password": "${SS_PASSWORD}",
        "network":  "tcp"
      },
      "streamSettings": {
        "network":      "grpc",
        "security":     "none",
        "grpcSettings": { "serviceName": "${SS_GRPC_SVC}" }
      }
    }

  ],

  "outbounds": [
    { "protocol": "freedom",   "tag": "direct" },
    { "protocol": "blackhole", "tag": "block"  }
  ],

  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type":        "field",
        "inboundTag":  ["api"],
        "outboundTag": "api"
      },
      {
        "type":        "field",
        "domain":      ["geosite:category-ads-all"],
        "outboundTag": "block"
      },
      {
        "type":        "field",
        "ip":          ["geoip:private"],
        "outboundTag": "direct"
      }
    ]
  }
}
