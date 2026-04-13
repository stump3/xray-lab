{
  "log": {
    "access": "/var/log/xray/access.log",
    "error":  "/var/log/xray/error.log",
    "loglevel": "warning"
  },

  "stats": {},
  "api": {
    "tag": "api",
    "services": ["StatsService", "HandlerService"]
  },
  "policy": {
    "levels": {
      "0": { "statsUserUplink": true, "statsUserDownlink": true }
    },
    "system": {
      "statsInboundUplink": false,
      "statsInboundDownlink": false
    }
  },

  "inbounds": [
    {
      "tag": "api",
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" }
    },

    {
      "tag": "vless-tls-main",
      "port": 443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id":    "${UUID_VLESS}",
            "email": "user-vless",
            "level": 0
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "path": "${VLESS_WS_PATH}",
            "dest": ${VLESS_WS_PORT},
            "xver": 1
          },
          {
            "path": "${VMESS_WS_PATH}",
            "dest": ${VMESS_WS_PORT},
            "xver": 1
          },
          {
            "dest": "${H1_SOCK}",
            "xver": 1
          }
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
          "alpn": ["http/1.1"]
        }
      }
    },

    {
      "tag": "vless-ws-in",
      "listen": "127.0.0.1",
      "port": ${VLESS_WS_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id":    "${UUID_VLESS}",
            "email": "user-vless-ws",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network":    "ws",
        "security":   "none",
        "wsSettings": {
          "path": "${VLESS_WS_PATH}",
          "acceptProxyProtocol": true
        }
      },
      "sniffing": {
        "enabled":      true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly":    true
      }
    },

    {
      "tag": "vmess-ws-in",
      "listen": "127.0.0.1",
      "port": ${VMESS_WS_PORT},
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id":    "${UUID_VMESS}",
            "email": "user-vmess-ws",
            "level": 0
          }
        ]
      },
      "streamSettings": {
        "network":    "ws",
        "security":   "none",
        "wsSettings": {
          "path": "${VMESS_WS_PATH}",
          "acceptProxyProtocol": true
        }
      },
      "sniffing": {
        "enabled":      true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly":    true
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
        "type":       "field",
        "inboundTag": ["api"],
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
