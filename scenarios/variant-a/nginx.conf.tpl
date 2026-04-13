# variant-a: Nginx только для subscription links и статики
# Xray сидит на :443, Nginx — на NGINX_PORT (по умолчанию 8080)
# Меняется одним числом: переменная NGINX_PORT в vars.env

pid ${NGINX_PID};

events {
    worker_connections 1024;
}

http {
    include      /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile     on;

    server {
        listen      ${NGINX_PORT};
        server_name _;

        # Subscription endpoint
        # Клиент опрашивает: http://SERVER_IP:8080/sub
        location /sub {
            alias /var/www/sub/;
            default_type text/plain;
            add_header Cache-Control "no-store, no-cache";
        }

        # Статика / decoy (опционально)
        location / {
            root  /var/www/html;
            index index.html;
        }
    }
}
