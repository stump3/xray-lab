{
  "log": {
    "loglevel": "info"
  },

  "inbounds": [
    {
      "tag":      "socks",
      "listen":   "127.0.0.1",
      "port":     ${SOCKS_PORT},
      "protocol": "socks",
      "settings": { "udp": true }
    },
    {
      "tag":      "http",
      "listen":   "127.0.0.1",
      "port":     ${HTTP_PORT},
      "protocol": "http"
    }
  ],

  "outbounds": [
    {
      "tag":      "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${SERVER_IP}",
            "port":    ${XRAY_PORT},
            "users": [
              {
                "id":         "${UUID}",
                "encryption": "none",
                "flow":       ""
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network":  "xhttp",
        "security": "reality",
        "xhttpSettings": {
          "path": "${XHTTP_PATH}",
          "mode": "auto"
        },
        "realitySettings": {
          "fingerprint": "chrome",
          "serverName":  "${REALITY_DOMAIN}",
          "publicKey":   "${PUB_KEY}",
          "shortId":     "${SHORT_ID}",
          "spiderX":     "/"
        }
      }
    },
    {
      "tag":      "direct",
      "protocol": "freedom"
    },
    {
      "tag":      "block",
      "protocol": "blackhole"
    }
  ],

  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type":        "field",
        "ip":          ["geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type":        "field",
        "domain":      ["geosite:category-ads-all"],
        "outboundTag": "block"
      }
    ]
  }
}
