#!/usr/bin/env bash
# install.sh — установка Xray-core и зависимостей для xray-lab
#
# Использование:
#   sudo bash scripts/install.sh
#   sudo bash scripts/install.sh --no-service   # без systemd (только бинарник)
#   sudo bash scripts/install.sh --arch arm64   # принудительная архитектура
set -euo pipefail

XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF_DIR="/usr/local/etc/xray"
XRAY_DAT_DIR="/usr/local/share/xray"
XRAY_LOG_DIR="/var/log/xray"
SYSTEMD_UNIT="/etc/systemd/system/xray-lab.service"
RELEASES_URL="https://github.com/XTLS/Xray-core/releases/latest/download"
RELEASES_API="https://api.github.com/repos/XTLS/Xray-core/releases/latest"

OPT_NO_SERVICE=false
OPT_ARCH=""

# ── Разбор аргументов ─────────────────────────────────────────────────────────

for arg in "$@"; do
    case "$arg" in
        --no-service) OPT_NO_SERVICE=true ;;
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
    echo "  1. Заполни переменные:"
    echo "     cp scenarios/variant-a/vars.env.example scenarios/variant-a/vars.env"
    echo "     nano scenarios/variant-a/vars.env"
    echo
    echo "  2. Сгенерируй ключи:    make keys"
    echo "  3. Проверь домен:       make check-domain D=www.microsoft.com"
    echo "  4. Запусти стек:        make up"
    echo "  5. Прогони тесты:       make test"
    echo "  6. Получи ссылку:       make link-qr"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    echo
    echo "  xray-lab installer"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    need_root
    install_deps
    install_xray
    set_cap
    create_dirs
    install_service
    print_next_steps
}

main
