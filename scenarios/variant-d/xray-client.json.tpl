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
            "address": "${DOMAIN}",
            "port":    443,
            "users": [
              {
                "id":         "${UUID}",
                "encryption": "none",
                "flow":       "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network":  "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName":  "${DOMAIN}",
          "fingerprint": "chrome",
          "alpn":        ["http/1.1"]
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
