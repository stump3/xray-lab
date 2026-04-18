# variant-c2 — Nginx на двух unix-сокетах, без TCP-порта
#
# h1.sock  — HTTP/1.1, PROXY protocol от Xray (default fallback)
#             Decoy сайт + subscription endpoint
#
# h2c.sock — HTTP/2 cleartext, PROXY protocol от @trojan-tcp fallback
#             Роутит gRPC-запросы по service name на Xray grpc inbounds
#
# Порядок запуска: Nginx сначала (создаёт сокеты), потом Xray.

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

    # ── HTTP/1.1: decoy сайт + subscription ──────────────────────────────────
    # Получает трафик из default fallback главного inbound (xver: 2)
    server {
        listen unix:${H1_SOCK} proxy_protocol;
        server_name ${DOMAIN} _;

        set_real_ip_from  unix:;
        real_ip_header    proxy_protocol;

        root  /var/www/html;
        index index.html;

        location ${SUB_PATH} {
            alias /var/www/sub/;
            default_type text/plain;
            add_header Cache-Control "no-store, no-cache";
        }

        location / {
            try_files ${DOLLAR}uri ${DOLLAR}uri/ =404;
        }
    }

    # ── HTTP/2 cleartext: gRPC routing ───────────────────────────────────────
    # Получает трафик из @trojan-tcp fallback (xver: 2) когда Trojan-auth провален
    # (т.е. gRPC-запросы). Nginx видит path и передаёт в нужный Xray grpc inbound.
    server {
        listen unix:${H2C_SOCK} proxy_protocol;
        http2  on;   # nginx >= 1.25.1; для 1.24 установи nginx-extras или обнови
        server_name ${DOMAIN} _;

        set_real_ip_from  unix:;
        real_ip_header    proxy_protocol;

        # Trojan gRPC
        location /${TROJAN_GRPC_SVC} {
            if (${DOLLAR}request_method != "POST") { return 404; }
            grpc_pass          grpc://127.0.0.1:${TROJAN_GRPC_PORT};
            grpc_set_header    X-Real-IP ${DOLLAR}proxy_protocol_addr;
            grpc_read_timeout  300s;
            grpc_send_timeout  300s;
        }

        # VLESS gRPC
        location /${VLESS_GRPC_SVC} {
            if (${DOLLAR}request_method != "POST") { return 404; }
            grpc_pass          grpc://127.0.0.1:${VLESS_GRPC_PORT};
            grpc_set_header    X-Real-IP ${DOLLAR}proxy_protocol_addr;
            grpc_read_timeout  300s;
            grpc_send_timeout  300s;
        }

        # VMess gRPC
        location /${VMESS_GRPC_SVC} {
            if (${DOLLAR}request_method != "POST") { return 404; }
            grpc_pass          grpc://127.0.0.1:${VMESS_GRPC_PORT};
            grpc_set_header    X-Real-IP ${DOLLAR}proxy_protocol_addr;
            grpc_read_timeout  300s;
            grpc_send_timeout  300s;
        }

        # Shadowsocks gRPC
        location /${SS_GRPC_SVC} {
            if (${DOLLAR}request_method != "POST") { return 404; }
            grpc_pass          grpc://127.0.0.1:${SS_GRPC_PORT};
            grpc_set_header    X-Real-IP ${DOLLAR}proxy_protocol_addr;
            grpc_read_timeout  300s;
            grpc_send_timeout  300s;
        }

        # Fallback decoy для h2c (probing, прямые браузерные запросы)
        location / {
            root  /var/www/html;
            index index.html;
            try_files ${DOLLAR}uri ${DOLLAR}uri/ =404;
        }
    }
}
