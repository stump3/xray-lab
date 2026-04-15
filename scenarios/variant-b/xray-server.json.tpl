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
      "tag": "reality-in",
      "listen": "127.0.0.1",
      "port": ${REALITY_INBOUND_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id":    "${UUID_REALITY}",
            "email": "user-reality",
            "level": 0,
            "flow":  "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network":  "tcp",
        "security": "reality",
        "realitySettings": {
          "show":        false,
          "target":      "${REALITY_DOMAIN}:443",
          "serverNames": ["${REALITY_DOMAIN}"],
          "privateKey":  "${PRIV_KEY}",
          "shortIds":    ["${SHORT_ID}", ""]
        }
      },
      "sniffing": {
        "enabled":      true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly":    true
      }
    },

    {
      "tag": "ws-in",
      "listen": "127.0.0.1",
      "port": ${WS_INBOUND_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id":    "${UUID_WS}",
            "email": "user-ws",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network":    "ws",
        "security":   "none",
        "wsSettings": { "path": "${WS_PATH}" }
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
