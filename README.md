# xray-lab

Лабораторный репозиторий для тестирования [Xray-core](https://github.com/XTLS/Xray-core) конфигураций перед внедрением в продакшн-скрипты.

Текущий сценарий: **Variant A** — VLESS + XHTTP + Reality, Xray напрямую на порту 443.

```
Internet :443 (TCP)
    │
    ▼
Xray  ── VLESS + XHTTP + Reality
    │
    └──  Nginx :8080  (опционально, subscription endpoint)
```

---

## Быстрый старт

```bash
# 1. Клонировать
git clone https://github.com/YOU/xray-lab && cd xray-lab

# 2. Установить xray-core и создать окружение
sudo bash scripts/install.sh

# 3. Заполнить переменные
cp scenarios/variant-a/vars.env.example scenarios/variant-a/vars.env
nano scenarios/variant-a/vars.env   # SERVER_IP, REALITY_DOMAIN

# 4. Сгенерировать ключи
make keys

# 5. Проверить decoy-домен
make check-domain D=www.microsoft.com

# 6. Поднять стек
make up

# 7. Прогнать тесты
make test

# 8. Получить vless:// ссылку + QR
make link-qr
```

---

## Структура

```
xray-lab/
├── scenarios/
│   └── variant-a/
│       ├── vars.env.example      ← переменные (SERVER_IP, ключи, домен)
│       ├── xray-server.json.tpl  ← серверный конфиг (шаблон)
│       ├── xray-client.json.tpl  ← клиентский конфиг (шаблон)
│       ├── nginx.conf.tpl        ← Nginx для sub endpoint (опционально)
│       ├── run.sh                ← up / down / client / logs / status
│       └── test.sh               ← server / domain / proxy тесты
├── scripts/
│   ├── install.sh                ← установка xray-core + зависимостей
│   ├── update.sh                 ← обновление xray-core до latest
│   └── uninstall.sh              ← полное удаление
├── tools/
│   ├── gen-keys.sh               ← x25519 + UUID + shortId
│   ├── gen-link.sh               ← vless:// ссылка + QR
│   └── check-domain.sh           ← проверка домена для Reality
├── docker/
│   └── compose.yml               ← изолированная среда (dev)
├── notes/
│   └── variant-a.md              ← дневник экспериментов
└── Makefile                      ← единая точка входа
```

---

## Команды

| Команда | Действие |
|---|---|
| `make init` | Создать `vars.env` из примера |
| `make keys` | Сгенерировать ключи → `vars.env` |
| `make up` | Запустить xray-сервер |
| `make down` | Остановить |
| `make client` | Запустить клиентский xray (SOCKS5 :1080) |
| `make test` | Все тесты |
| `make test-server` | Только серверные тесты |
| `make test-proxy` | Только тест прокси |
| `make link-qr` | vless:// ссылка + QR-код |
| `make check-domain D=…` | Проверить домен для Reality |
| `sudo make install` | Установить xray-core |
| `sudo make update` | Обновить xray-core |
| `sudo make uninstall` | Полное удаление |

---

## Требования

- Linux (Debian/Ubuntu/CentOS)
- `curl`, `unzip`, `jq`, `openssl`
- `qrencode` (опционально, для QR-кодов)
- Root для установки и запуска на порту 443

---

## Путь в продакшн

После успешного теста конфиги переезжают в xray-manager:

```
xray-server.json.tpl → add_xhttp_reality_inbound() в 04-xray-core.sh
test.sh              → test/test_xray_core.bats
tools/gen-link.sh    → gen_link() в 04-xray-core.sh
```

---

## Лицензия

MIT
