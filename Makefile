# xray-lab Makefile
VAR   ?= variant-a
D     ?= www.microsoft.com
SHELL := bash

SCENARIO := scenarios/$(VAR)
TOOLS    := tools
SCRIPTS  := scripts

.PHONY: help choose select install install-no-service update update-check update-auto rollback uninstall uninstall-force reinstall init init-auto quickstart quickstart-auto keys up down restart client logs status test test-server test-domain test-proxy link link-qr link-save link-sub check-domain

help:
	@echo ""
	@echo "  xray-lab — управление лабораторным стендом Xray"
	@echo ""
	@echo "  Выбор варианта и инициализация:"
	@echo "    make choose               Выбрать вариант (↑↓ стрелки) → init"
	@echo "    make quickstart           choose → keys → up → link-qr"
	@echo "    make quickstart-auto      init-auto → keys → up (VAR=$(VAR), без вопросов)"
	@echo "    make init                 Инициализировать vars.env для VAR=$(VAR)"
	@echo "    make init-auto            То же, без вопросов"
	@echo "    make keys                 Сгенерировать ключи"
	@echo ""
	@echo "  Установка и обслуживание xray-core:"
	@echo "    make install              Установить xray-core"
	@echo "    make update               Обновить (интерактивно)"
	@echo "    make update-check         Проверить версию"
	@echo "    make update-auto          Обновить без подтверждения (cron)"
	@echo "    make rollback             Откат к предыдущей версии"
	@echo "    make uninstall            Полное удаление (интерактивно)"
	@echo "    make reinstall            Снести + переустановить + up + test (vars.env сохраняется)"
	@echo ""
	@echo "  Стенд [VAR=$(VAR)]:"
	@echo "    make up                   Запустить стек"
	@echo "    make down                 Остановить"
	@echo "    make restart              Перезапустить"
	@echo "    make client               Клиентский xray (SOCKS5 :1080)"
	@echo "    make logs / status"
	@echo ""
	@echo "  Тесты:  make test / test-server / test-domain / test-proxy"
	@echo "  Ссылки: make link / link-qr / link-save / link-sub"
	@echo "  Домен:  make check-domain D=$(D)"
	@echo ""

# ── Выбор варианта ────────────────────────────────────────────────────────────

# Интерактивный выбор стрелками ↑↓, затем init.sh выбранного варианта.
# VAR= при этом игнорируется — вариант определяется в UI.
choose select:
	@CHOSEN=$$(bash $(TOOLS)/choose-variant.sh) || exit 1; \
	bash scenarios/$$CHOSEN/init.sh

# ── Установка и обслуживание xray-core ───────────────────────────────────────

install:
	sudo bash $(SCRIPTS)/install.sh

install-no-service:
	sudo bash $(SCRIPTS)/install.sh --no-service

update:
	sudo bash $(SCRIPTS)/update.sh

update-check:
	sudo bash $(SCRIPTS)/update.sh --check

update-auto:
	sudo bash $(SCRIPTS)/update.sh --auto

rollback:
	sudo bash $(SCRIPTS)/update.sh --rollback

uninstall:
	sudo bash $(SCRIPTS)/uninstall.sh

uninstall-force:
	sudo bash $(SCRIPTS)/uninstall.sh --force

reinstall:
	sudo bash $(SCRIPTS)/install.sh --reinstall
	@bash $(SCENARIO)/run.sh up
	@bash $(SCENARIO)/test.sh all

# ── Инициализация ─────────────────────────────────────────────────────────────

init:
	@bash $(SCENARIO)/init.sh

init-auto:
	@bash $(SCENARIO)/init.sh --auto

# choose → init → keys → [certbot] → up → link-qr (вариант выбирается в UI)
quickstart:
	@CHOSEN=$$(bash $(TOOLS)/choose-variant.sh) || exit 1; \
	XRAY_QUICKSTART=1 bash scenarios/$$CHOSEN/init.sh && \
	bash $(TOOLS)/gen-keys.sh --write $$CHOSEN && \
	bash $(TOOLS)/maybe-certbot.sh $$CHOSEN && \
	bash scenarios/$$CHOSEN/run.sh up && \
	bash $(TOOLS)/gen-link.sh $$CHOSEN --qr

# init-auto → keys → up → link-qr (без вопросов, VAR= обязателен)
quickstart-auto: init-auto
	@bash $(TOOLS)/gen-keys.sh --write $(VAR)
	@bash $(SCENARIO)/run.sh up
	@bash $(TOOLS)/gen-link.sh $(VAR) --qr

keys: init
	@bash $(TOOLS)/gen-keys.sh --write $(VAR)

# ── Управление стеком ─────────────────────────────────────────────────────────

up:
	@bash $(SCENARIO)/run.sh up

down:
	@bash $(SCENARIO)/run.sh down

restart:
	@bash $(SCENARIO)/run.sh restart

client:
	@bash $(SCENARIO)/run.sh client

logs:
	@bash $(SCENARIO)/run.sh logs

status:
	@bash $(SCENARIO)/run.sh status

# ── Тесты ─────────────────────────────────────────────────────────────────────

test:
	@bash $(SCENARIO)/test.sh all

test-server:
	@bash $(SCENARIO)/test.sh server

test-domain:
	@bash $(SCENARIO)/test.sh domain

test-proxy:
	@bash $(SCENARIO)/test.sh proxy

# ── Ссылки ────────────────────────────────────────────────────────────────────

link:
	@bash $(TOOLS)/gen-link.sh $(VAR)

link-qr:
	@bash $(TOOLS)/gen-link.sh $(VAR) --qr

link-save:
	@bash $(TOOLS)/gen-link.sh $(VAR) --save

link-sub:
	@bash $(TOOLS)/gen-link.sh $(VAR) --sub

# ── Инструменты ───────────────────────────────────────────────────────────────

check-domain:
	@bash $(TOOLS)/check-domain.sh $(D)
