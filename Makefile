# xray-lab Makefile
VAR   ?= variant-a
D     ?= www.microsoft.com
SHELL := bash

SCENARIO := scenarios/$(VAR)
TOOLS    := tools
SCRIPTS  := scripts

.PHONY: help install install-no-service update update-check update-auto rollback uninstall uninstall-force init keys up down restart client logs status test test-server test-domain test-proxy link link-qr link-save check-domain

help:
	@echo ""
	@echo "  xray-lab — управление лабораторным стендом Xray"
	@echo ""
	@echo "  Установка и обслуживание xray-core:"
	@echo "    make install              Установить xray-core"
	@echo "    make update               Обновить (интерактивно)"
	@echo "    make update-check         Проверить версию"
	@echo "    make update-auto          Обновить без подтверждения (cron)"
	@echo "    make rollback             Откат к предыдущей версии"
	@echo "    make uninstall            Полное удаление"
	@echo ""
	@echo "  Стенд [VAR=$(VAR)]:"
	@echo "    make init                 Создать vars.env"
	@echo "    make keys                 Сгенерировать ключи"
	@echo "    make up                   Запустить xray-сервер"
	@echo "    make down                 Остановить"
	@echo "    make client               Клиентский xray (SOCKS5 :1080)"
	@echo "    make logs / status"
	@echo ""
	@echo "  Тесты:  make test / test-server / test-domain / test-proxy"
	@echo "  Ссылки: make link / link-qr / link-save"
	@echo "  Домен:  make check-domain D=$(D)"
	@echo ""

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

init:
	@bash $(SCENARIO)/init.sh

keys: init
	@bash $(TOOLS)/gen-keys.sh --write $(VAR)

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

test:
	@bash $(SCENARIO)/test.sh all

test-server:
	@bash $(SCENARIO)/test.sh server

test-domain:
	@bash $(SCENARIO)/test.sh domain

test-proxy:
	@bash $(SCENARIO)/test.sh proxy

link:
	@bash $(TOOLS)/gen-link.sh $(VAR)

link-qr:
	@bash $(TOOLS)/gen-link.sh $(VAR) --qr

link-save:
	@bash $(TOOLS)/gen-link.sh $(VAR) --save

check-domain:
	@bash $(TOOLS)/check-domain.sh $(D)
