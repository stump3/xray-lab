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
      "tag": "vless-tls-vision",
      "port": 443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id":    "${UUID}",
            "email": "user-1",
            "level": 0,
            "flow":  "xtls-rprx-vision"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": ${NGINX_DECOY_PORT}
          }
        ]
      },
      "streamSettings": {
        "network":  "tcp",
        "security": "tls",
        "tlsSettings": {
          "fingerprint": "chrome",
          "alpn":        ["http/1.1"],
          "certificates": [
            {
              "certificateFile": "${CERT_FILE}",
              "keyFile":         "${KEY_FILE}"
            }
          ]
        }
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
