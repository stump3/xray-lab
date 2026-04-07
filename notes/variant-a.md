# Variant A — VLESS + XHTTP + Reality на порту 443

## Архитектура

```
Internet :443 (TCP)
    │
    ▼
Xray (VLESS + XHTTP + Reality)    ← занимает весь порт 443
    │
    └── Nginx :8080                ← опционально, subscription endpoint
```

## Что тестируем

- [ ] Xray стартует без ошибок
- [ ] TLS handshake с decoy domain проходит (`./test.sh server`)
- [ ] SOCKS5 прокси работает (`./test.sh proxy`)
- [ ] Внешний IP совпадает с SERVER_IP
- [ ] DNS не течёт (socks5h, не socks5)
- [ ] vless:// ссылка открывается в Shadowrocket / NekoBox / v2rayN

## Параметры окружения

| Параметр | Значение |
|---|---|
| SERVER_IP | |
| REALITY_DOMAIN | |
| XHTTP_PATH | |
| XRAY_PORT | 443 |
| Клиент | Shadowrocket / NekoBox / v2rayN |

## Результаты

### Запуск

```
date:
xray version:
```

### Тесты

```
(вставь вывод ./test.sh all)
```

### Наблюдения

-

### Проблемы и решения

-

## Что переходит в xray-manager

После успешного теста:

- `xray-server.json.tpl` → шаблон в `add_xhttp_reality_inbound()` в `04-xray-core.sh`
- параметры Reality → аргументы функции + `save_reality_keys()`
- логика `test.sh` → bats-тесты в `test/test_xray_core.bats`
