#!/usr/bin/env bash
# install.sh — установка Xray-core и зависимостей для xray-lab
#
# Использование:
#   sudo bash scripts/install.sh
#   sudo bash scripts/install.sh --no-service   # без systemd (только бинарник)
#   sudo bash scripts/install.sh --arch arm64   # принудительная архитектура
#   sudo bash scripts/install.sh --reinstall    # чистая переустановка без вопросов
set -euo pipefail

XRAY_BIN="/usr/local/bin/xray"
XRAY_BIN_PREV="/usr/local/bin/xray.prev"
XRAY_CONF_DIR="/usr/local/etc/xray"
XRAY_DAT_DIR="/usr/local/share/xray"
XRAY_LOG_DIR="/var/log/xray"
SYSTEMD_UNIT="/etc/systemd/system/xray-lab.service"
TMP_RUN_DIR="/tmp/xray-lab-variant-a"
RELEASES_URL="https://github.com/XTLS/Xray-core/releases/latest/download"
RELEASES_API="https://api.github.com/repos/XTLS/Xray-core/releases/latest"

OPT_NO_SERVICE=false
OPT_ARCH=""
OPT_REINSTALL=false   # --reinstall: чистая переустановка без вопросов

# ── Разбор аргументов ─────────────────────────────────────────────────────────

for arg in "$@"; do
    case "$arg" in
        --no-service) OPT_NO_SERVICE=true ;;
        --reinstall)  OPT_REINSTALL=true ;;
        --arch)       shift; OPT_ARCH="$1" ;;
        --arch=*)     OPT_ARCH="${arg#*=}" ;;
    esac
done

# ── Хелперы ───────────────────────────────────────────────────────────────────

info()  { echo "  [·] $*"; }
ok()    { echo "  [✓] $*"; }
warn()  { echo "  [!] $*" >&2; }
die()   { echo "  [✗] $*" >&2; exit 1; }
need_root() { [[ "$(id -u)" -eq 0 ]] || die "Нужен root: sudo bash $0"; }

# ── Обнаружение существующей установки ───────────────────────────────────────

detect_existing() {
    local found=()
    [[ -x "$XRAY_BIN" ]]                     && found+=("бинарник $XRAY_BIN")
    [[ -f "$SYSTEMD_UNIT" ]]                  && found+=("systemd-юнит xray-lab")
    [[ -d "$XRAY_CONF_DIR" ]]                 && found+=("конфиги $XRAY_CONF_DIR")
    [[ "${#found[@]}" -eq 0 ]]                && return 0   # чистая система — продолжаем

    echo
    echo "  ┌─────────────────────────────────────────────────────┐"
    echo "  │  Обнаружена существующая установка:                  │"
    for item in "${found[@]}"; do
        printf "  │    • %-48s│\n" "$item"
    done
    if [[ -x "$XRAY_BIN" ]]; then
        local ver; ver="$("$XRAY_BIN" version 2>/dev/null | awk 'NR==1{print $2}')"
        printf "  │    Версия: %-42s│\n" "$ver"
    fi
    echo "  └─────────────────────────────────────────────────────┘"
    echo

    if $OPT_REINSTALL; then
        info "--reinstall: чистая переустановка без вопросов"
        do_clean_reinstall
        return
    fi

    echo "  Что делаем?"
    echo "    1) Обновить бинарник          — ключи и vars.env не трогаем"
    echo "    2) Чистая переустановка       — снести всё*, поставить заново"
    echo "    3) Выйти"
    echo
    echo "  * vars.env и notes/ не удаляются"
    echo
    local choice
    while true; do
        read -r -p "  Выбор [1/2/3]: " choice
        case "$choice" in
            1) return 0 ;;          # продолжить обычный install (перезапишет бинарник)
            2) do_clean_reinstall; return 0 ;;
            3) echo "  Отменено."; exit 0 ;;
            *) echo "  Введи 1, 2 или 3" ;;
        esac
    done
}

# ── Чистая переустановка ──────────────────────────────────────────────────────

do_clean_reinstall() {
    info "Останавливаем службу..."
    systemctl stop xray-lab 2>/dev/null    && ok "Служба остановлена" || true
    systemctl disable xray-lab 2>/dev/null || true

    info "Удаляем старые файлы..."
    setcap -r "$XRAY_BIN" 2>/dev/null     || true
    rm -f  "$XRAY_BIN" "$XRAY_BIN_PREV"
    rm -f  "$SYSTEMD_UNIT"
    rm -rf "$XRAY_CONF_DIR" "$XRAY_DAT_DIR" "$XRAY_LOG_DIR" "$TMP_RUN_DIR"
    systemctl daemon-reload 2>/dev/null   || true
    ok "Старая установка удалена (vars.env и notes/ сохранены)"
    echo
}

# ── Определение архитектуры ───────────────────────────────────────────────────

detect_arch() {
    if [[ -n "$OPT_ARCH" ]]; then
        XRAY_ARCH="$OPT_ARCH"
        return
    fi
    case "$(uname -m)" in
        x86_64)  XRAY_ARCH="64" ;;
        aarch64|arm64) XRAY_ARCH="arm64-v8a" ;;
        armv7*)  XRAY_ARCH="arm32-v7a" ;;
        *)       die "Неизвестная архитектура: $(uname -m). Укажи вручную: --arch 64" ;;
    esac
    info "Архитектура: $(uname -m) → Xray-linux-${XRAY_ARCH}"
}

# ── Зависимости ───────────────────────────────────────────────────────────────

install_deps() {
    info "Проверка зависимостей..."
    local need=()
    for p in curl unzip jq openssl make; do
        command -v "$p" &>/dev/null || need+=("$p")
    done
    command -v qrencode &>/dev/null || warn "qrencode не найден — QR-коды недоступны (опционально)"

    if [[ ${#need[@]} -gt 0 ]]; then
        info "Устанавливаем: ${need[*]}"
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && apt-get install -y -qq "${need[@]}"
        elif command -v yum &>/dev/null; then
            yum install -y -q "${need[@]}"
        elif command -v dnf &>/dev/null; then
            dnf install -y -q "${need[@]}"
        else
            die "Пакетный менеджер не найден. Установи вручную: ${need[*]}"
        fi
    fi
    ok "Зависимости в порядке"
}

# ── Загрузка и установка Xray-core ───────────────────────────────────────────

install_xray() {
    detect_arch

    local zip_name="Xray-linux-${XRAY_ARCH}.zip"
    local url="${RELEASES_URL}/${zip_name}"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap "rm -rf '$tmp_dir'" EXIT

    info "Загружаем ${zip_name}..."
    curl -fL --progress-bar -o "${tmp_dir}/xray.zip" "$url" \
        || die "Не удалось загрузить ${url}"

    info "Распаковываем..."
    unzip -qo "${tmp_dir}/xray.zip" -d "${tmp_dir}/xray/" \
        || die "Ошибка распаковки"

    install -m 755 "${tmp_dir}/xray/xray" "$XRAY_BIN" \
        || die "Не удалось установить бинарник"

    # Геобазы
    mkdir -p "$XRAY_DAT_DIR"
    for dat in geoip.dat geosite.dat; do
        [[ -f "${tmp_dir}/xray/${dat}" ]] \
            && install -m 644 "${tmp_dir}/xray/${dat}" "${XRAY_DAT_DIR}/${dat}" \
            || true
    done

    local ver
    ver="$("$XRAY_BIN" version 2>/dev/null | head -1)"
    ok "Установлен: ${ver}"
}

# ── Capability (порт < 1024 без root) ─────────────────────────────────────────

set_cap() {
    if command -v setcap &>/dev/null; then
        setcap cap_net_bind_service=+ep "$XRAY_BIN" \
            && info "CAP_NET_BIND_SERVICE установлен" \
            || warn "setcap не удался — запускайте xray от root"
    else
        warn "setcap не найден (пакет libcap2-bin) — порт 443 требует root"
    fi
}

# ── Структура директорий ──────────────────────────────────────────────────────

create_dirs() {
    mkdir -p "$XRAY_CONF_DIR" "$XRAY_LOG_DIR"
    chown nobody:nogroup "$XRAY_LOG_DIR" 2>/dev/null || \
    chown nobody:nobody  "$XRAY_LOG_DIR" 2>/dev/null || true
    ok "Директории созданы"
}

# ── Systemd-юнит (лабораторный, не продакшн) ─────────────────────────────────

install_service() {
    $OPT_NO_SERVICE && { info "Пропускаем systemd (--no-service)"; return; }

    # Юнит ожидает конфиг в /tmp/xray-lab-variant-a/xray-server.json
    # Это позволяет менять конфиг без правки юнита
    cat > "$SYSTEMD_UNIT" << 'EOF'
[Unit]
Description=xray-lab — тестовый Xray-core
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
# Конфиг рендерится через run.sh и кладётся сюда:
Environment=XRAY_CONF=/tmp/xray-lab-variant-a/xray-server.json
ExecStartPre=/bin/sh -c 'test -f ${XRAY_CONF} || (echo "Конфиг не найден: ${XRAY_CONF}. Запусти make up" >&2 && exit 1)'
ExecStart=/usr/local/bin/xray run -c /tmp/xray-lab-variant-a/xray-server.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=1000000
# Логи через journald (дополнительно к файловым логам xray)
StandardOutput=journal
StandardError=journal
SyslogIdentifier=xray-lab

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$SYSTEMD_UNIT"
    systemctl daemon-reload
    ok "systemd-юнит установлен: ${SYSTEMD_UNIT}"
    info "Управление: systemctl {start|stop|status|enable} xray-lab"
    info "Логи:       journalctl -u xray-lab -f"
}

# ── Итог ──────────────────────────────────────────────────────────────────────

print_next_steps() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Установка завершена. Следующие шаги:"
    echo
    if [[ -f "$(dirname "$0")/../scenarios/variant-a/vars.env" ]]; then
        # vars.env уже есть — скорее всего обновление или переустановка с сохранением
        echo "  vars.env найден — ключи на месте:"
        echo "    make up          ← сразу запустить стек"
        echo "    make test        ← прогнать тесты"
        echo "    make link-qr     ← ссылка + QR"
    else
        echo "  Интерактивный запуск (рекомендуется):"
        echo "    make quickstart      ← настройка + ключи + up + QR за один шаг"
        echo
        echo "  Или пошагово:"
        echo "    make init            ← заполнить vars.env (IP подтянется сам)"
        echo "    make keys            ← сгенерировать ключи"
        echo "    make up              ← запустить xray"
        echo "    make test            ← прогнать тесты"
        echo "    make link-qr         ← ссылка + QR"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    echo
    echo "  xray-lab installer"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    need_root
    detect_existing
    install_deps
    install_xray
    set_cap
    create_dirs
    install_service
    print_next_steps
}

main
