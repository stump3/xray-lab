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
      "tag":      "proxy-reality",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${SERVER_IP}",
            "port":    443,
            "users": [
              {
                "id":         "${UUID_REALITY}",
                "encryption": "none",
                "flow":       "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network":  "tcp",
        "security": "reality",
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
