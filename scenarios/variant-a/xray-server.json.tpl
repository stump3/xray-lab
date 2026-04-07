{
  "log": {
    "access": "/var/log/xray/access.log",
    "error":  "/var/log/xray/error.log",
    "loglevel": "warning"
  },

  "stats": {},
  "api": {
    "tag": "api",
    "services": ["StatsService"]
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
      "tag": "vless-xhttp-reality",
      "listen": "0.0.0.0",
      "port": ${XRAY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id":    "${UUID}",
            "email": "user-1",
            "level": 0,
            "flow":  ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network":  "xhttp",
        "security": "reality",
        "xhttpSettings": {
          "path": "${XHTTP_PATH}",
          "mode": "auto"
        },
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
