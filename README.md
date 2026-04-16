# xray-lab

Лабораторный стенд для тестирования [Xray-core](https://github.com/XTLS/Xray-core) конфигураций перед переносом в продакшн-скрипты. Каждый сценарий — изолированный стек со своими шаблонами, переменными и тестами.

```
Internet :443
    │
    ├── Variant A  — Xray напрямую (VLESS+XHTTP+Reality)
    ├── Variant B  — Nginx stream SNI routing (Reality + WS на одном порту)
    ├── Variant C  — Xray native fallbacks, All-in-One (VLESS+TLS+Vision)
    ├── Variant C2 — All-in-One расширенный: 17 протоколов (VLESS/VMess/Trojan/SS)
    └── Variant D  — Self-SNI: собственный decoy-сайт (VLESS+TLS+Vision)
```

---

## Выбор варианта

| | A | B | C | C2 | D |
|---|---|---|---|---|---|
| Reality (без сертификата) | ✅ | ✅ | ❌ | ❌ | ❌ |
| WS/gRPC через CDN на :443 | ❌ | ✅ | ✅ | ✅ | ❌ |
| Нужен TLS-сертификат | ❌ | ✅ | ✅ | ✅ | ✅ |
| Нужен собственный домен | ❌ | ✅ | ✅ | ✅ | ✅ |
| Нужен wildcard сертификат | ❌ | ❌ | ❌ | ✅ | ❌ |
| Decoy — собственный сайт | ❌ | ❌ | ❌ | ❌ | ✅ |
| Число протоколов на :443 | 1 | 2 | 2 | 17 | 1 |
| Сложность | Низкая | Средняя | Высокая | Очень высокая | Низкая |

- **Нет домена, максимальная скрытность** → Variant A
- **Reality + CDN-протоколы на одном :443** → Variant B
- **Несколько протоколов, панель управления** → Variant C
- **Максимум протоколов (VLESS/VMess/Trojan/SS × TCP/WS/gRPC/H2)** → Variant C2
- **Собственный сайт, IP = домен = сертификат** → Variant D

---

## Общие требования

- Linux (Debian / Ubuntu / CentOS)
- `curl`, `unzip`, `jq`, `openssl`, `make`, `gettext-base` (`envsubst`)
- `qrencode` — опционально, для QR-кодов
- `nginx` — нужен для вариантов B, C, C2, D
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
make init
make keys
make check-domain D=www.microsoft.com
make up
make test
make link-qr
```

Или одной командой:

```bash
make quickstart
```

### vars.env

```bash
cp scenarios/variant-a/vars.env.example scenarios/variant-a/vars.env
# Затем make keys (заполнит UUID, PRIV_KEY, PUB_KEY, SHORT_ID)
```

| Параметр | Описание |
|---|---|
| `REALITY_DOMAIN` | Decoy-домен без Cloudflare, TLS 1.3 + HTTP/2 |
| `XHTTP_PATH` | Случайный путь, генерируется автоматически |
| `XRAY_PORT` | Порт Xray-сервера (443) |
| `NGINX_PORT` | Порт subscription endpoint (8080, произвольный) |

### Тесты

```bash
make test              # все тесты
make test-server       # порты и конфиг
make test-domain       # decoy-домен (TLS 1.3 + HTTP/2 + без Cloudflare)
make test-proxy        # проксирование через SOCKS5
```

---

## Variant B — Nginx stream SNI routing

Nginx занимает :443, читает SNI из ClientHello и маршрутизирует поток до TLS handshake.

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
certbot certonly --standalone -d your-domain.com
make init VAR=variant-b
make keys VAR=variant-b
make up VAR=variant-b
make test VAR=variant-b
make link-qr VAR=variant-b
```

### vars.env

| Параметр | Описание |
|---|---|
| `DOMAIN` | Собственный домен (для Nginx HTTPS + WS) |
| `REALITY_DOMAIN` | Decoy-домен для Reality |
| `REALITY_INBOUND_PORT` | Xray Reality inbound (8443, только loopback) |
| `WS_INBOUND_PORT` | Xray WS inbound (9001, только loopback) |
| `NGINX_HTTPS_PORT` | Nginx HTTPS server (7443, только loopback) |

### Тесты

```bash
make test VAR=variant-b
make test-server VAR=variant-b
make test-routing VAR=variant-b   # SNI routing: два SNI → два сертификата
make test-proxy VAR=variant-b
```

> Убедись что установлен `nginx-full` (`apt install nginx-full`). Обычный `nginx-light` не имеет модуля stream.

---

## Variant C — Xray native fallbacks (All-in-One)

Xray занимает :443 и сам управляет TLS. Маршрутизация через fallbacks по `path`. Nginx на unix socket (без TCP-порта).

```
Internet :443 (TCP)
    │
    ▼
Xray VLESS+TLS (TLS-терминация)
    ├── path=/VLESS_WS_PATH  →  VLESS WS inbound :9001
    ├── path=/VMESS_WS_PATH  →  VMess WS inbound :9002
    └── default              →  unix:H1_SOCK  (Nginx decoy + /sub)
```

**Требования:** собственный домен + TLS-сертификат.

> **Reality недоступна в Variant C и C2.** Reality работает до TLS handshake; fallbacks работают после расшифровки. Это взаимоисключающие механизмы.

### Быстрый старт

```bash
certbot certonly --standalone -d your-domain.com
make init VAR=variant-c
make keys VAR=variant-c
make up VAR=variant-c
make test VAR=variant-c
make link-qr VAR=variant-c
```

### vars.env

| Параметр | Описание |
|---|---|
| `DOMAIN` | Собственный домен |
| `VLESS_WS_PATH` / `VMESS_WS_PATH` | Пути для fallback-маршрутизации |
| `VLESS_WS_PORT` / `VMESS_WS_PORT` | Порты sub-inbounds (9001, 9002) |
| `H1_SOCK` | Unix socket для Nginx decoy (`/dev/shm/xraylab-c-h1.sock`) |

### Тесты

```bash
make test VAR=variant-c
make test-server VAR=variant-c     # :443, sub-inbounds, unix socket
make test-fallback VAR=variant-c   # TLS, fallback → decoy, WS path
make test-proxy VAR=variant-c
```

---

## Variant C2 — All-in-One расширенный (17 протоколов)

Полная реализация `XTLS/Xray-examples — All-in-One-fallbacks-Nginx`. VLESS+Vision+TLS на :443 → дерево fallbacks → 17 протоколов. Nginx на двух unix-сокетах: `h1.sock` (decoy) и `h2c.sock` (gRPC routing).

```
Internet :443 (TCP)
    │
    ▼
Xray VLESS+Vision+TLS (TLS-терминация)
    │
    ├── SNI+ALPN=h2 → H2 sub-inbounds (trh2o/vlh2o/vmh2o/ssh2o.DOMAIN)
    │     Trojan H2 · VLESS H2 · VMess H2 · SS H2
    │
    ├── path=...   → WS + TCP obfs sub-inbounds
    │     VLESS WS · VMess WS · Trojan WS · SS WS
    │     VLESS TCP · VMess TCP · SS TCP
    │
    ├── alpn=h2    → @trojan-tcp
    │                   ├── Trojan TCP (валидный пароль)
    │                   └── gRPC → h2c.sock → Nginx → grpc_pass
    │                         Trojan gRPC · VLESS gRPC · VMess gRPC · SS gRPC
    │
    └── default    → h1.sock → Nginx → decoy сайт + /sub
```

**Требования:** собственный домен + wildcard TLS-сертификат (`DOMAIN + *.DOMAIN`) + nginx с `http_v2_module`.

### Быстрый старт

```bash
# Wildcard сертификат (покрывает H2 субдомены: trh2o, vlh2o, vmh2o, ssh2o)
certbot certonly --standalone -d your-domain.com -d *.your-domain.com

# DNS: добавить A-записи для H2 субдоменов → SERVER_IP
# trh2o.your-domain.com, vlh2o.your-domain.com, vmh2o.your-domain.com, ssh2o.your-domain.com

make init VAR=variant-c2
make keys VAR=variant-c2       # генерирует UUID, TR_PASSWORD, SS_PASSWORD
make up VAR=variant-c2
make test VAR=variant-c2
make link-qr VAR=variant-c2    # выводит все 17 ссылок
```

### vars.env

| Параметр | Описание |
|---|---|
| `UUID` | Единый UUID для VLESS и VMess |
| `TR_PASSWORD` | Пароль для Trojan (генерируется через `make keys`) |
| `SS_PASSWORD` | Ключ для Shadowsocks 2022 (base64, генерируется через `make keys`) |
| `SS_METHOD` | `2022-blake3-aes-128-gcm` |
| `DOMAIN` | Основной домен |
| `VLESS_WS_PATH` … `SS_TC_PATH` | 7 случайных путей (генерируются автоматически) |
| `TROJAN_GRPC_PORT` … `SS_H2_PORT` | 7 внутренних портов (3001–4003) |
| `H1_SOCK` / `H2C_SOCK` | Unix sockets (`/dev/shm/xraylab-c2-*.sock`) |

### Subscription links

`make link-qr VAR=variant-c2` выводит все 17 ссылок с нумерацией:

| # | Протокол |
|---|---|
| C2-01 | VLESS + Vision + TLS |
| C2-02 | VLESS + TCP + HTTP obfs + TLS |
| C2-03 | VLESS + WebSocket + TLS (CDN) |
| C2-04 | VLESS + gRPC + TLS (CDN) |
| C2-05 | VLESS + H2 + TLS |
| C2-06 | VMess + TCP + HTTP obfs + TLS |
| C2-07 | VMess + WebSocket + TLS (CDN) |
| C2-08 | VMess + gRPC + TLS (CDN) |
| C2-09 | VMess + H2 + TLS |
| C2-10 | Trojan + TCP + TLS |
| C2-11 | Trojan + WebSocket + TLS (CDN) |
| C2-12 | Trojan + gRPC + TLS (CDN) |
| C2-13 | Trojan + H2 + TLS |
| C2-14 | Shadowsocks + WebSocket |
| C2-15 | Shadowsocks + TCP obfs |
| C2-16 | Shadowsocks + gRPC |
| C2-17 | Shadowsocks + H2 |

### Тесты

```bash
make test VAR=variant-c2
make test-server VAR=variant-c2    # :443 + 7 портов + 2 unix socket
make test-fallback VAR=variant-c2  # TLS + fallback → decoy + WS path
make test-domain VAR=variant-c2    # сертификат + wildcard SAN
make test-proxy VAR=variant-c2     # SOCKS5 → VLESS+Vision+TLS
```

> **Порядок запуска критичен:** `run.sh up` запускает Nginx первым (создаёт `h1.sock` и `h2c.sock`), затем ждёт оба сокета и только потом стартует Xray.

---

## Variant D — Self-SNI

Xray занимает :443 с VLESS+TLS+Vision. Нераспознанный трафик падает через fallback на Nginx, который отдаёт реальный сайт на том же IP.

```
Internet :443 (TCP)              Internet :80
    │                                │
    ▼                                ▼
Xray VLESS+TLS+Vision         Nginx (301 → HTTPS)
    ├── Клиент «свой» → прокси
    └── Всё остальное → fallback → Nginx 127.0.0.1:8080 → decoy сайт
```

**Требования:** собственный домен + TLS-сертификат.

**Ключевое отличие от Reality:** IP, домен, сертификат и сайт принадлежат одному серверу — полностью согласованная легенда. В Reality decoy — сторонний сайт на другом IP.

### Быстрый старт

```bash
certbot certonly --standalone -d your-domain.com
make init VAR=variant-d
make keys VAR=variant-d
make up VAR=variant-d
make test VAR=variant-d
make link-qr VAR=variant-d
```

### vars.env

| Параметр | Описание |
|---|---|
| `DOMAIN` | Собственный домен (совпадает с DNS A и с сертификатом) |
| `NGINX_DECOY_PORT` | Порт decoy Nginx (8080, только 127.0.0.1, произвольный) |
| `CERT_FILE` / `KEY_FILE` | TLS-сертификат |

### Тесты

```bash
make test VAR=variant-d
make test-server VAR=variant-d
make test-legend VAR=variant-d    # DNS = SERVER_IP, redirect, decoy, нет Cloudflare
make test-proxy VAR=variant-d
```

---

## Команды Makefile (все варианты)

Все команды принимают `VAR=` для выбора сценария. Дефолт: `variant-a`.

```bash
make <cmd> VAR=variant-c2
```

| Команда | Действие |
|---|---|
| `make init` | Создать `vars.env` интерактивно |
| `make init-auto` | Создать `vars.env` без вопросов |
| `make keys` | Сгенерировать ключи → `vars.env` |
| `make quickstart` | init + keys + up + link-qr |
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
│   │   └── ...  + gen-link.sh  ← 2 ссылки: Reality + WS
│   ├── variant-c/               ← Xray native fallbacks
│   │   └── ...  + gen-link.sh  ← 2 ссылки: VLESS+WS + VMess+WS
│   ├── variant-c2/              ← All-in-One расширенный
│   │   └── ...  + gen-link.sh  ← 17 ссылок (C2-01 … C2-17)
│   └── variant-d/               ← Self-SNI
│       └── ...  + gen-link.sh  ← 1 ссылка: VLESS+TCP+TLS+Vision
├── scripts/
│   ├── install.sh               ← установка xray-core + зависимостей
│   ├── update.sh                ← обновление, --check, --auto, --rollback
│   └── uninstall.sh             ← полное удаление
├── tools/
│   ├── gen-keys.sh              ← x25519 + UUID(s) + пароли, вариант-aware
│   ├── gen-link.sh              ← диспетчер → scenarios/<VAR>/gen-link.sh
│   ├── select-variant.sh        ← интерактивный TUI выбор варианта
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
