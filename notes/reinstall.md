# Чистая переустановка xray-lab

## Когда это нужно

- Стек не стартует и `make logs` не даёт очевидной причины
- Xray обновился мажорно и формат конфига сломался
- Хочешь начать с нуля с новыми ключами
- Переезд `vars.env` на другой сервер

---

## Сценарий 1 — Полный сброс (новые ключи, новый конфиг)

Удаляет всё включая `vars.env`. Подходит для смены ключей или чистого деплоя.

```bash
# 1. Снести стек и бинарник
sudo make uninstall          # спросит подтверждение
# или без вопросов:
sudo bash scripts/uninstall.sh --force

# 2. Убедиться, что порт свободен
ss -tlnp | grep :443         # должно быть пусто

# 3. Удалить репозиторий целиком (вместе с vars.env)
cd ~
rm -rf xray-lab

# 4. Склонировать заново и установить
git clone https://github.com/stump3/xray-lab && cd xray-lab
sudo bash scripts/install.sh
make quickstart              # init (интерактивно) → keys → up → link-qr
```

---

## Сценарий 2 — Переустановка с сохранением ключей

`vars.env` (UUID, ключи, IP) остаётся нетронутым — клиентские конфиги менять не нужно.

```bash
# 1. Остановить все варианты
make down                            # variant-a
make down VAR=variant-b              # если использовался variant-b
# ... и т.д. для других вариантов

# 2. Снести бинарник (vars.env не удаляется)
sudo bash scripts/uninstall.sh --force

# 3. Переустановить xray-core
sudo bash scripts/install.sh

# 4. Поднять стек с теми же ключами
make up                              # variant-a (дефолт)
make up VAR=variant-b                # если нужен variant-b

# 5. Проверить
make test
make link-qr                         # ссылка та же, что и до переустановки
```

---

## Сценарий 3 — Обновление бинарника без сброса

Только xray-core обновляется, конфиг и ключи не трогаются.

```bash
make update-check            # посмотреть доступную версию
make update                  # обновить (интерактивно, с подтверждением)
# или без вопросов (для cron):
make update-auto

# Откат если что-то сломалось:
make rollback
```

---

## Сценарий 4 — Переезд на другой сервер

```bash
# На старом сервере — сохранить vars.env
cat scenarios/variant-a/vars.env        # скопировать содержимое

# На новом сервере:
git clone https://github.com/stump3/xray-lab && cd xray-lab
sudo bash scripts/install.sh

# Вариант А — восстановить старые ключи вручную:
make init                    # интерактивно — введи новый IP, остальное Enter
# затем отредактировать UUID/PRIV_KEY/PUB_KEY/SHORT_ID в vars.env
# вставив значения со старого сервера

# Вариант Б — новые ключи (нужно обновить клиентские конфиги):
make quickstart              # init → keys → up → link-qr
```

---

## Что удаляет `uninstall.sh` — что остаётся

| Путь | Удаляется? | Примечание |
|---|---|---|
| `/usr/local/bin/xray` | ✅ да | бинарник |
| `/usr/local/bin/xray.prev` | ✅ да | резервная копия для rollback |
| `/usr/local/etc/xray/` | ✅ да | рабочие конфиги (рендер из шаблонов) |
| `/usr/local/share/xray/` | ✅ да | геобазы geoip.dat / geosite.dat |
| `/var/log/xray/` | ✅ да | логи |
| `/tmp/xray-lab-variant-a/` | ✅ да | временные файлы variant-a |
| `/tmp/xray-lab-variant-b/` | ✅ да | временные файлы variant-b |
| `/tmp/xray-lab-variant-c/` | ✅ да | временные файлы variant-c (+ unix socket) |
| `/tmp/xray-lab-variant-d/` | ✅ да | временные файлы variant-d |
| `/etc/systemd/system/xray-lab.service` | ✅ да | systemd-юнит |
| `scenarios/*/vars.env` | ❌ нет | UUID, ключи — спрашивается отдельно для каждого варианта |
| `notes/` | ❌ нет | дневник экспериментов |
| `scenarios/*/vars.env.example` | ❌ нет | шаблоны |

> `--keep-bin` сохраняет бинарник xray, удаляет всё остальное.

> После удаления `uninstall.sh` автоматически восстанавливает системный nginx (`systemctl start nginx`), если он был установлен и включён в автозапуск.

---

## Быстрая диагностика перед переустановкой

```bash
make status                  # состояние процессов
make status VAR=variant-b    # для конкретного варианта
make logs                    # хвост логов (variant-a)
make logs VAR=variant-b      # логи variant-b
make test-server             # порты и конфиг

# Проверить, занят ли порт другим процессом
ss -tlnp | grep :443
lsof -i :443

# Посмотреть рабочий конфиг (после make up)
cat /tmp/xray-lab-variant-a/xray-server.json
cat /tmp/xray-lab-variant-b/xray-server.json

# Валидация конфига вручную
xray run -test -c /tmp/xray-lab-variant-a/xray-server.json
xray run -test -c /tmp/xray-lab-variant-b/xray-server.json
```

---

## Типичные причины переустановки и их решение без сброса

| Симптом | Решение без переустановки |
|---|---|
| `xray: command not found` | `sudo bash scripts/install.sh` |
| Порт занят после `make up` | `make down`, затем `make up` |
| Конфиг не рендерится | проверить `vars.env` на незаполненные плейсхолдеры |
| `xray run -test -c ...` падает с ошибкой JSON | откатить конфиг: `make down && make up` |
| Новая версия xray ломает конфиг | `make rollback` |
| Ключи скомпрометированы | Сценарий 1 (полный сброс) |
