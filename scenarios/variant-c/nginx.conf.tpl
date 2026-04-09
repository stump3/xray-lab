# variant-c — Nginx на unix socket (нет TCP-порта)
# Xray делает TLS-терминацию на :443 и через fallback (xver: 1) передаёт
# нераспознанный трафик сюда. Nginx получает реальный IP через PROXY protocol.
# Рендерится через envsubst с явным списком переменных (см. run.sh).

user www-data;
worker_processes auto;
pid ${NGINX_PID};

events {
    worker_connections 1024;
}

http {
    include      /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile     on;

    # Реальный IP пользователя приходит в PROXY protocol от Xray (xver: 1)
    set_real_ip_from 127.0.0.1;
    real_ip_header   proxy_protocol;

    server {
        # unix socket + proxy_protocol: Xray пишет сюда нераспознанный трафик
        listen unix:${H1_SOCK} proxy_protocol;
        server_name ${DOMAIN} _;

        root  /var/www/html;
        index index.html;

        # Subscription endpoint
        location ${SUB_PATH} {
            alias /var/www/sub/;
            default_type text/plain;
            add_header Cache-Control "no-store, no-cache";
        }

        location / {
            try_files ${DOLLAR}uri ${DOLLAR}uri/ =404;
        }
    }
}
