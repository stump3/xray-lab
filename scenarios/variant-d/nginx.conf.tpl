# variant-d — Nginx: HTTP→HTTPS redirect + decoy сайт на loopback
#
# :80       — публичный, только redirect → HTTPS
# :8080     — только 127.0.0.1, decoy сайт для Xray fallback
#             Снаружи напрямую недоступен — Nginx не слушает на 0.0.0.0:8080
#
# HSTS добавлен на decoy: при активном probing цензор видит легитимный
# заголовок безопасности — дополнительный признак реального веб-сервера.

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

    # ── HTTP: только redirect → HTTPS ─────────────────────────────────────────
    server {
        listen 80;
        server_name ${DOMAIN};
        return 301 https://${DOLLAR}host${DOLLAR}request_uri;
    }

    # ── Decoy сайт: только loopback, Xray fallback пишет сюда ────────────────
    # Снаружи по IP/домену:80 — только redirect выше.
    # По HTTPS напрямую на 8080 снаружи — недоступен (listen 127.0.0.1 only).
    server {
        listen 127.0.0.1:${NGINX_DECOY_PORT};
        server_name ${DOMAIN} _;

        root  /var/www/html;
        index index.html;

        # HSTS: браузер/проверяющий инструмент видит стандартный заголовок
        add_header Strict-Transport-Security "max-age=63072000" always;

        location / {
            try_files ${DOLLAR}uri ${DOLLAR}uri/ =404;
        }
    }
}
