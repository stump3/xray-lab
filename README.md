# xray-lab

Лабораторный стенд для тестирования [Xray-core](https://github.com/XTLS/Xray-core) конфигураций перед переносом в продакшн-скрипты. Каждый сценарий — изолированный стек со своими шаблонами, переменными и тестами.

```
Internet :443
    │
    ├── Variant A — Xray напрямую (VLESS+XHTTP+Reality)
    ├── Variant B — Nginx stream SNI routing (Reality + WS на одном порту)
    ├── Variant C — Xray native fallbacks, All-in-One (VLESS+TLS+Vision)
    └── Variant D — Self-SNI: собственный decoy-сайт (VLESS+TLS+Vision)
```

---

## Выбор варианта

| | A | B | C | D |
|---|---|---|---|---|
| Reality (без сертификата) | ✅ | ✅ | ❌ | ❌ |
| WS/gRPC через CDN на :443 | ❌ | ✅ | ✅ | ❌ |
| Нужен TLS-сертификат | ❌ | ✅ | ✅ | ✅ |
| Нужен собственный домен | ❌ | ✅ | ✅ | ✅ |
| Decoy — собственный сайт | ❌ | ❌ | ❌ | ✅ |
| Сложность | Низкая | Средняя | Высокая | Низкая |

- **Нет домена, максимальная скрытность** → Variant A
- **Reality + CDN-протоколы на одном :443** → Variant B
- **Максимум протоколов, панель управления** → Variant C
- **Собственный сайт, IP = домен = сертификат** → Variant D

---

## Общие требования

- Linux (Debian / Ubuntu / CentOS)
- `curl`, `unzip`, `jq`, `openssl`, `make`, `gettext-base` (`envsubst`)
- `qrencode` — опционально, для QR-кодов
- `nginx` — нужен для вариантов B, C, D
- Root для запуска на порту 443

Установка xray-core (один раз, для всех вариантов):

```bash
sudo bash scripts/install.sh
```

---

## Variant A — VLESS + XHTTP + Reality

Xray занимает порт 443 целиком. Nginx работает на произвольном порту только как subscription endpoint — между ними нет связи.

```
Internet :443 (TCP)
    │
    ▼
Xray (VLESS + XHTTP + Reality)
    │
    └── Nginx :8080  (опционально, subscription endpoint)
```

**Требования:** нет (ни домена, ни сертификата).

### Быстрый старт

```bash
# Инициализировать vars.env (IP подтянется автоматически)
make init

# Сгенерировать ключи (UUID, x25519, shortId)
make keys

# Проверить decoy-домен перед запуском
make check-domain D=www.microsoft.com

# Запустить стек
make up

# Прогнать тесты
make test

# Получить ссылку + QR-код
make link-qr
```

Или одной командой:

```bash
make quickstart
```

### vars.env

```bash
cp scenarios/variant-a/vars.env.example scenarios/variant-a/vars.env
# Отредактировать: SERVER_IP, REALITY_DOMAIN, XHTTP_PATH
# Затем make keys (заполнит UUID, PRIV_KEY, PUB_KEY, SHORT_ID)
```

Ключевые параметры:

| Параметр | Описание |
|---|---|
| `REALITY_DOMAIN` | Decoy-домен без Cloudflare, TLS 1.3 + HTTP/2 |
| `XHTTP_PATH` | Случайный путь, генерируется автоматически |
| `XRAY_PORT` | Порт Xray-сервера (443) |
| `NGINX_PORT` | Порт subscription endpoint (8080, произвольный) |

### Subscription link

```
vless://UUID@SERVER_IP:443
  ?security=reality&type=xhttp
  &pbk=PUB_KEY&sid=SHORT_ID&sni=REALITY_DOMAIN
  &fp=chrome&path=XHTTP_PATH
```

### Тесты

```bash
make test              # все тесты
make test-server       # порты и конфиг
make test-domain       # decoy-домен (TLS 1.3 + HTTP/2 + без Cloudflare)
make test-proxy        # проксирование через SOCKS5
```

---

## Variant B — Nginx stream SNI routing

Nginx занимает :443, читает SNI из ClientHello и маршрутизирует поток до TLS handshake. Reality-клиенты идут напрямую в Xray. Клиенты по домену — в Nginx HTTPS, откуда WS проксируется в Xray.

```
Internet :443 (TCP)
    │
    ▼
Nginx stream (SNI routing)
    ├── SNI = DOMAIN       →  Nginx HTTPS :7443
    │                            ├── /         → decoy сайт
    │                            ├── /sub      → subscription endpoint
    │                            └── /WS_PATH  → Xray WS inbound :9001
    └── SNI = всё остальное →  Xray Reality :8443
                                   └── VLESS+TCP+Vision+Reality
```

**Требования:** собственный домен + TLS-сертификат + nginx-full (с модулем stream).

### Быстрый старт

```bash
# Получить сертификат до запуска стека
certbot certonly --standalone -d your-domain.com

# Инициализировать vars.env
make init VAR=variant-b

# Сгенерировать ключи (UUID_REALITY, UUID_WS, x25519, shortId)
make keys VAR=variant-b

# Запустить стек
make up VAR=variant-b

# Тесты
make test VAR=variant-b

# Ссылки (Reality + WS) + QR
make link-qr VAR=variant-b
```

### vars.env

```bash
cp scenarios/variant-b/vars.env.example scenarios/variant-b/vars.env
# Заполнить: DOMAIN, REALITY_DOMAIN, SERVER_IP, CERT_FILE, KEY_FILE
# Затем make keys VAR=variant-b
```

Ключевые параметры:

| Параметр | Описание |
|---|---|
| `DOMAIN` | Собственный домен (для Nginx HTTPS + WS) |
| `REALITY_DOMAIN` | Decoy-домен для Reality |
| `REALITY_INBOUND_PORT` | Xray Reality inbound (8443, только loopback) |
| `WS_INBOUND_PORT` | Xray WS inbound (9001, только loopback) |
| `NGINX_HTTPS_PORT` | Nginx HTTPS server (7443, только loopback) |
| `WS_PATH` | Путь для WebSocket |
| `CERT_FILE` / `KEY_FILE` | TLS-сертификат для домена |

> Все внутренние порты (8443, 9001, 7443) выбираются произвольно — меняются одновременно в vars.env и подхватываются шаблонами автоматически.

### Subscription links

```
# Reality (прямой клиент, без CDN):
vless://UUID_REALITY@SERVER_IP:443
  ?security=reality&type=tcp&flow=xtls-rprx-vision
  &pbk=PUB_KEY&sid=SHORT_ID&sni=REALITY_DOMAIN&fp=chrome

# WebSocket + TLS (CDN-совместимый):
vless://UUID_WS@DOMAIN:443
  ?security=tls&type=ws&path=WS_PATH&sni=DOMAIN&fp=chrome
```

### Тесты

```bash
make test VAR=variant-b           # все тесты
make test-server VAR=variant-b    # порты: :443, :8443, :9001, :7443
make test-routing VAR=variant-b   # SNI routing: два SNI → два разных сертификата
make test-domain VAR=variant-b    # decoy-домен (TLS 1.3 + HTTP/2)
make test-proxy VAR=variant-b     # проксирование через Reality
```

> **Nginx stream module:** убедись что установлен `nginx-full` (`apt install nginx-full`). Обычный `nginx-light` не имеет модуля stream. Вариант B проверяет это при старте и выводит инструкцию если модуль отсутствует.

---

## Variant C — Xray native fallbacks (All-in-One)

Xray занимает :443 и сам управляет TLS. После расшифровки смотрит на `path` и маршрутизирует в sub-inbound через fallback. Nginx не имеет TCP-порта — слушает только на unix socket.

```
Internet :443 (TCP)
    │
    ▼
Xray VLESS+TLS (TLS-терминация)
    ├── path=/VLESS_WS_PATH  →  VLESS WS inbound :9001
    ├── path=/VMESS_WS_PATH  →  VMess WS inbound :9002
    └── default              →  unix:H1_SOCK  (Nginx decoy)
                                     └── /sub → subscription endpoint
```

**Требования:** собственный домен + TLS-сертификат.

> **Reality недоступна в Variant C.** Reality работает до TLS handshake; fallbacks работают после расшифровки. Это взаимоисключающие механизмы.

### Быстрый старт

```bash
# Получить сертификат
certbot certonly --standalone -d your-domain.com

# Инициализировать vars.env
make init VAR=variant-c

# Сгенерировать UUID (x25519 не нужен — Reality нет)
make keys VAR=variant-c

# Убедиться что /dev/shm доступен (unix socket)
ls /dev/shm

# Запустить стек (Nginx стартует первым — создаёт unix socket)
make up VAR=variant-c

# Тесты
make test VAR=variant-c

# Ссылки (VLESS+WS+TLS + VMess+WS+TLS) + QR
make link-qr VAR=variant-c
```

### vars.env

```bash
cp scenarios/variant-c/vars.env.example scenarios/variant-c/vars.env
# Заполнить: DOMAIN, SERVER_IP, CERT_FILE, KEY_FILE
# Затем make keys VAR=variant-c
```

Ключевые параметры:

| Параметр | Описание |
|---|---|
| `DOMAIN` | Собственный домен |
| `VLESS_WS_PATH` / `VMESS_WS_PATH` | Пути для fallback-маршрутизации |
| `VLESS_WS_PORT` / `VMESS_WS_PORT` | Порты sub-inbounds (9001, 9002) |
| `H1_SOCK` | Unix socket для Nginx decoy (`/dev/shm/xraylab-c-h1.sock`) |
| `CERT_FILE` / `KEY_FILE` | TLS-сертификат (Xray терминирует TLS напрямую) |

### Subscription links

```
# VLESS + WebSocket + TLS:
vless://UUID_VLESS@DOMAIN:443
  ?security=tls&type=ws&path=VLESS_WS_PATH&sni=DOMAIN&fp=chrome

# VMess + WebSocket + TLS:
vmess://base64({add,port,id,net,path,tls,sni,fp,...})
```

### Тесты

```bash
make test VAR=variant-c             # все тесты
make test-server VAR=variant-c      # :443, sub-inbounds, unix socket
make test-fallback VAR=variant-c    # TLS, fallback → decoy, WS path → sub-inbound
make test-domain VAR=variant-c      # сертификат (файл, срок, ключ)
make test-proxy VAR=variant-c       # SOCKS5 → VLESS+WS+TLS
```

> **Порядок запуска важен:** `run.sh up` запускает Nginx первым и ждёт появления unix socket перед запуском Xray. При ручном управлении соблюдать тот же порядок.

---

## Variant D — Self-SNI

Xray занимает :443 с VLESS+TLS+Vision. Нераспознанный трафик (HTTP-запросы, active probing) падает через fallback на Nginx, который отдаёт реальный сайт на том же IP. Nginx на :80 делает redirect на HTTPS.

```
Internet :443 (TCP)              Internet :80
    │                                │
    ▼                                ▼
Xray VLESS+TLS+Vision         Nginx (301 → HTTPS)
    ├── Клиент «свой» → прокси
    └── Всё остальное → fallback → Nginx 127.0.0.1:8080
                                        └── decoy сайт (реальный HTML)
```

**Требования:** собственный домен + TLS-сертификат.

**Ключевое отличие от Reality:** в Reality decoy — сторонний сайт на другом IP (microsoft.com). При active probing IP сервера ≠ IP microsoft.com — расхождение детектируемо. В Self-SNI IP, домен, сертификат и сайт принадлежат одному серверу — полностью согласованная легенда.

**Ключевое отличие от Variant C:** Variant C оптимизирован на количество протоколов (unix sockets, дерево fallbacks). Variant D — на максимальную простоту и достоверность легенды: один fallback, обычный TCP-порт, нет unix sockets.

> **Reality и CDN недоступны.** `xtls-rprx-vision` несовместим с Cloudflare и CDN-прокси.

### Быстрый старт

```bash
# Получить сертификат (DNS A-запись должна уже указывать на SERVER_IP)
certbot certonly --standalone -d your-domain.com

# Инициализировать vars.env
make init VAR=variant-d

# Сгенерировать UUID (x25519 не нужен — TLS, не Reality)
make keys VAR=variant-d

# Положить что-нибудь в decoy-сайт (опционально, но желательно)
echo '<html><body>Hello</body></html>' | sudo tee /var/www/html/index.html

# Запустить стек (Nginx стартует первым)
make up VAR=variant-d

# Тесты (включая проверку согласованности легенды)
make test VAR=variant-d

# Ссылка + QR
make link-qr VAR=variant-d
```

### vars.env

```bash
cp scenarios/variant-d/vars.env.example scenarios/variant-d/vars.env
# Заполнить: DOMAIN, SERVER_IP, CERT_FILE, KEY_FILE
# NGINX_DECOY_PORT=8080 (только 127.0.0.1, произвольный)
# Затем make keys VAR=variant-d
```

Ключевые параметры:

| Параметр | Описание |
|---|---|
| `DOMAIN` | Собственный домен (совпадает с DNS A и с сертификатом) |
| `NGINX_DECOY_PORT` | Порт decoy Nginx (8080, только 127.0.0.1, произвольный) |
| `CERT_FILE` / `KEY_FILE` | TLS-сертификат (Xray терминирует TLS напрямую) |

### Subscription link

```
vless://UUID@DOMAIN:443
  ?security=tls&type=tcp&flow=xtls-rprx-vision
  &alpn=http%2F1.1&fp=chrome&spx=%2F
```

### Тесты

```bash
make test VAR=variant-d           # все тесты
make test-server VAR=variant-d    # :443, :80, 127.0.0.1:DECOY_PORT
make test-legend VAR=variant-d    # DNS = SERVER_IP, TLS для DOMAIN, redirect, decoy, нет Cloudflare
make test-domain VAR=variant-d    # сертификат (файл, срок, ключ совпадает с сертом)
make test-proxy VAR=variant-d     # SOCKS5 → VLESS+TCP+TLS+Vision
```

> `test-legend` — уникальная проверка, специфичная для Self-SNI: верифицирует все 5 элементов легенды одновременно. Запускай перед переносом в продакшн.

---

## Команды Makefile (все варианты)

Все команды принимают `VAR=` для выбора сценария. Дефолт: `variant-a`.

```bash
make <cmd> VAR=variant-b
```

| Команда | Действие |
|---|---|
| `make init` | Создать `vars.env` интерактивно |
| `make init-auto` | Создать `vars.env` без вопросов |
| `make keys` | Сгенерировать ключи → `vars.env` |
| `make quickstart` | init + keys + up + link-qr |
| `make quickstart-auto` | То же, без вопросов |
| `make up` | Запустить стек |
| `make down` | Остановить |
| `make restart` | Перезапустить |
| `make client` | Запустить клиентский Xray (SOCKS5 :1080) |
| `make logs` | Хвост логов |
| `make status` | Статус процессов и портов |
| `make test` | Все тесты |
| `make test-server` | Серверные тесты (порты, конфиг) |
| `make test-proxy` | Тест проксирования через SOCKS5 |
| `make link` | Subscription ссылка на экран |
| `make link-qr` | Ссылка + QR-код |
| `make link-save` | Сохранить в `notes/` |
| `make check-domain D=…` | Проверить домен для Reality (A/B) |

Установка и обслуживание xray-core (без `VAR=`):

```bash
sudo make install          # установить xray-core
sudo make update           # обновить до latest
sudo make update-auto      # обновить без подтверждения (cron)
sudo make rollback         # откат к предыдущей версии
sudo make uninstall        # полное удаление
sudo make reinstall        # снести + переустановить + up + test
```

---

## Структура репозитория

```
xray-lab/
├── scenarios/
│   ├── variant-a/               ← VLESS+XHTTP+Reality
│   │   ├── vars.env.example
│   │   ├── vars.env             ← создаётся через make init (в .gitignore)
│   │   ├── xray-server.json.tpl
│   │   ├── xray-client.json.tpl
│   │   ├── nginx.conf.tpl
│   │   ├── init.sh
│   │   ├── run.sh
│   │   └── test.sh
│   ├── variant-b/               ← Nginx stream SNI routing
│   │   └── ...  + gen-link.sh  ← генерирует 2 ссылки (Reality + WS)
│   ├── variant-c/               ← Xray native fallbacks
│   │   └── ...  + gen-link.sh  ← генерирует 2 ссылки (VLESS+WS + VMess+WS)
│   └── variant-d/               ← Self-SNI
│       └── ...  + gen-link.sh  ← генерирует 1 ссылку (VLESS+TCP+TLS+Vision)
├── scripts/
│   ├── install.sh               ← установка xray-core + зависимостей
│   ├── update.sh                ← обновление, --check, --auto, --rollback
│   └── uninstall.sh             ← полное удаление
├── tools/
│   ├── gen-keys.sh              ← x25519 + UUID(s) + shortId, вариант-aware
│   ├── gen-link.sh              ← диспетчер → scenarios/<VAR>/gen-link.sh
│   └── check-domain.sh          ← TLS 1.3 + HTTP/2 + Cloudflare проверка
├── docker/
│   └── compose.yml              ← dev-среда (variant-a)
├── notes/
│   ├── variant-a.md             ← дневник экспериментов
│   └── reinstall.md             ← гайд по переустановке
└── Makefile
```

---

## Путь в продакшн

После успешного теста конфиги переезжают в xray-manager:

| Файл лаба | Куда в xray-manager |
|---|---|
| `xray-server.json.tpl` | шаблон в соответствующем `add_*_inbound()` |
| `test.sh` | `test/test_xray_*.bats` |
| `gen-link.sh` | `gen_link()` в `04-xray-core.sh` |
| `nginx.conf.tpl` | шаблон в `07-nginx.sh` |

---

## Лицензия

MIT
