# variant-b — полный nginx.conf с stream (SNI routing) + http блоком
# Рендерится через envsubst с явным списком переменных (см. run.sh)
# Nginx-переменные ($host, $http_upgrade и т.п.) в шаблоне экранированы через ${DOLLAR}

user www-data;
worker_processes auto;
pid /run/nginx-xraylab-b.pid;

events {
    worker_connections 1024;
}

# ── Stream: читает SNI до TLS handshake, маршрутизирует TCP-поток ─────────────
stream {
    map ${DOLLAR}ssl_preread_server_name ${DOLLAR}backend {
        ${DOMAIN}    nginx_https;
        default      xray_reality;
    }

    upstream xray_reality { server 127.0.0.1:${REALITY_INBOUND_PORT}; }
    upstream nginx_https  { server 127.0.0.1:${NGINX_HTTPS_PORT}; }

    server {
        listen      443;
        ssl_preread on;
        proxy_pass  ${DOLLAR}backend;
    }
}

# ── HTTP: HTTPS-сервер для домена + WS proxy на Xray WS inbound ───────────────
http {
    include      /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile     on;

    server {
        listen      ${NGINX_HTTPS_PORT} ssl;
        server_name ${DOMAIN};

        ssl_certificate     ${CERT_FILE};
        ssl_certificate_key ${KEY_FILE};
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;

        root  /var/www/html;
        index index.html;

        # Subscription endpoint
        location ${SUB_PATH} {
            alias /var/www/sub/;
            default_type text/plain;
            add_header Cache-Control "no-store, no-cache";
        }

        # WS → Xray WS inbound
        location ${WS_PATH} {
            proxy_pass          http://127.0.0.1:${WS_INBOUND_PORT};
            proxy_http_version  1.1;
            proxy_set_header    Upgrade ${DOLLAR}http_upgrade;
            proxy_set_header    Connection "upgrade";
            proxy_set_header    Host ${DOLLAR}host;
            proxy_read_timeout  86400s;
        }

        location / {
            try_files ${DOLLAR}uri ${DOLLAR}uri/ =404;
        }
    }
}
