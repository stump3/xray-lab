#!/usr/bin/env bash
# update.sh — обновление Xray-core до последней версии
#
# Использование:
#   sudo bash scripts/update.sh              — интерактивное обновление
#   sudo bash scripts/update.sh --auto       — без подтверждения (для cron/CI)
#   sudo bash scripts/update.sh --check      — только проверить версию, не обновлять
#   sudo bash scripts/update.sh --rollback   — откат к предыдущей версии
#
# Автообновление через cron (пример — каждый день в 04:00):
#   0 4 * * * root /path/to/xray-lab/scripts/update.sh --auto >> /var/log/xray-lab-update.log 2>&1
set -euo pipefail

XRAY_BIN="/usr/local/bin/xray"
XRAY_DAT_DIR="/usr/local/share/xray"
BACKUP_BIN="/usr/local/bin/xray.prev"
RELEASES_URL="https://github.com/XTLS/Xray-core/releases/latest/download"
RELEASES_API="https://api.github.com/repos/XTLS/Xray-core/releases/latest"
SERVICE_NAME="xray-lab"

OPT_AUTO=false
OPT_CHECK=false
OPT_ROLLBACK=false

# ── Аргументы ─────────────────────────────────────────────────────────────────

for arg in "$@"; do
    case "$arg" in
        --auto)     OPT_AUTO=true ;;
        --check)    OPT_CHECK=true ;;
        --rollback) OPT_ROLLBACK=true ;;
    esac
done

# ── Хелперы ───────────────────────────────────────────────────────────────────

info()     { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [·] $*"; }
ok()       { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [✓] $*"; }
warn()     { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [!] $*" >&2; }
die()      { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [✗] $*" >&2; exit 1; }
need_root(){ [[ "$(id -u)" -eq 0 ]] || die "Нужен root: sudo bash $0"; }

# ── Версии ────────────────────────────────────────────────────────────────────

current_ver() {
    [[ -x "$XRAY_BIN" ]] || { echo ""; return; }
    "$XRAY_BIN" version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo ""
}

latest_ver() {
    curl -fsSL --max-time 10 "$RELEASES_API" 2>/dev/null \
        | jq -r '.tag_name' \
        | grep -oP '[\d.]+' \
        | head -1 || echo ""
}

# ── Определение архитектуры ───────────────────────────────────────────────────

detect_arch() {
    case "$(uname -m)" in
        x86_64)        XRAY_ARCH="64" ;;
        aarch64|arm64) XRAY_ARCH="arm64-v8a" ;;
        armv7*)        XRAY_ARCH="arm32-v7a" ;;
        *)             die "Неизвестная архитектура: $(uname -m)" ;;
    esac
}

# ── Служба ────────────────────────────────────────────────────────────────────

service_running() {
    systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null
}

service_stop() {
    if service_running; then
        info "Останавливаем ${SERVICE_NAME}..."
        systemctl stop "$SERVICE_NAME"
        ok "Служба остановлена"
    fi
}

service_start() {
    if systemctl list-units --all --quiet "${SERVICE_NAME}.service" 2>/dev/null | grep -q xray; then
        info "Запускаем ${SERVICE_NAME}..."
        systemctl start "$SERVICE_NAME" && ok "Служба запущена" || warn "Служба не запустилась — проверь конфиг"
    fi
}

# ── Откат ─────────────────────────────────────────────────────────────────────

rollback() {
    [[ -x "$BACKUP_BIN" ]] || die "Резервная копия не найдена: ${BACKUP_BIN}"

    local prev_ver
    prev_ver="$("$BACKUP_BIN" version 2>/dev/null | grep -oP '[\d.]+' | head -1)"
    local cur_ver
    cur_ver="$(current_ver)"

    info "Откат: v${cur_ver} → v${prev_ver}"

    service_stop
    cp "$BACKUP_BIN" "$XRAY_BIN"
    chmod 755 "$XRAY_BIN"
    setcap cap_net_bind_service=+ep "$XRAY_BIN" 2>/dev/null || true
    service_start

    ok "Откат выполнен: $(current_ver)"
}

# ── Проверка версии ───────────────────────────────────────────────────────────

check_only() {
    local cur latest
    cur="$(current_ver)"
    latest="$(latest_ver)"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Установлена: v${cur:-не установлен}"
    echo "  Последняя:   v${latest:-недоступна}"

    if [[ -z "$latest" ]]; then
        echo "  Статус:      ⚠ не удалось получить версию с GitHub"
        exit 1
    elif [[ "$cur" == "$latest" ]]; then
        echo "  Статус:      ✓ актуальная версия"
        exit 0
    else
        echo "  Статус:      ↑ доступно обновление"
        exit 2   # non-zero чтобы cron/CI мог отреагировать
    fi
}

# ── Обновление ────────────────────────────────────────────────────────────────

do_update() {
    local cur latest
    cur="$(current_ver)"
    latest="$(latest_ver)"

    if [[ -z "$latest" ]]; then
        die "Не удалось получить актуальную версию с GitHub"
    fi

    info "Установлена: v${cur:-—}  Последняя: v${latest}"

    if [[ "$cur" == "$latest" ]]; then
        ok "Уже установлена актуальная версия v${latest} — обновление не нужно"
        exit 0
    fi

    # Подтверждение (не в автоматическом режиме)
    if ! $OPT_AUTO; then
        read -r -p "  Обновить v${cur} → v${latest}? [y/N] " reply
        [[ "$reply" =~ ^[Yy]$ ]] || { info "Отменено"; exit 0; }
    else
        info "Автообновление: v${cur} → v${latest}"
    fi

    detect_arch
    local zip_name="Xray-linux-${XRAY_ARCH}.zip"
    local url="${RELEASES_URL}/${zip_name}"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap "rm -rf '$tmp_dir'" EXIT

    # Резервная копия текущего бинарника
    if [[ -x "$XRAY_BIN" ]]; then
        cp "$XRAY_BIN" "$BACKUP_BIN"
        info "Резервная копия: ${BACKUP_BIN} (v${cur})"
    fi

    local was_running=false
    service_running && was_running=true
    service_stop

    # Загрузка
    info "Загружаем ${zip_name}..."
    curl -fL --progress-bar -o "${tmp_dir}/xray.zip" "$url" \
        || { warn "Загрузка не удалась — откат"; rollback; exit 1; }

    info "Распаковываем..."
    unzip -qo "${tmp_dir}/xray.zip" -d "${tmp_dir}/xray/" \
        || { warn "Ошибка распаковки — откат"; rollback; exit 1; }

    install -m 755 "${tmp_dir}/xray/xray" "$XRAY_BIN" \
        || { warn "Ошибка установки — откат"; rollback; exit 1; }

    # Геобазы (если поставлялись в архиве)
    for dat in geoip.dat geosite.dat; do
        [[ -f "${tmp_dir}/xray/${dat}" ]] \
            && install -m 644 "${tmp_dir}/xray/${dat}" "${XRAY_DAT_DIR}/${dat}" \
            || true
    done

    # Восстановление capability
    setcap cap_net_bind_service=+ep "$XRAY_BIN" 2>/dev/null \
        && info "CAP_NET_BIND_SERVICE восстановлен" || true

    # Быстрая проверка бинарника
    "$XRAY_BIN" version &>/dev/null \
        || { warn "Новый бинарник не работает — откат"; rollback; exit 1; }

    $was_running && service_start

    local new_ver
    new_ver="$(current_ver)"
    ok "Обновление выполнено: v${cur} → v${new_ver}"
    info "Откат доступен: sudo bash scripts/update.sh --rollback"
}

# ── Main ──────────────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  xray-lab update"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

need_root

if $OPT_ROLLBACK; then
    rollback
    exit 0
fi

if $OPT_CHECK; then
    check_only
    exit $?
fi

do_update
