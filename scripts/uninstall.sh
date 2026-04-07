#!/usr/bin/env bash
# uninstall.sh — полное удаление xray-lab и Xray-core
#
# Использование:
#   sudo bash scripts/uninstall.sh             — интерактивное (запрашивает подтверждение)
#   sudo bash scripts/uninstall.sh --force     — без подтверждения
#   sudo bash scripts/uninstall.sh --keep-bin  — удалить всё кроме бинарника xray
set -euo pipefail

XRAY_BIN="/usr/local/bin/xray"
XRAY_BIN_PREV="/usr/local/bin/xray.prev"
XRAY_CONF_DIR="/usr/local/etc/xray"
XRAY_DAT_DIR="/usr/local/share/xray"
XRAY_LOG_DIR="/var/log/xray"
SYSTEMD_UNIT="/etc/systemd/system/xray-lab.service"
TMP_DIR="/tmp/xray-lab-variant-a"

OPT_FORCE=false
OPT_KEEP_BIN=false

for arg in "$@"; do
    case "$arg" in
        --force)    OPT_FORCE=true ;;
        --keep-bin) OPT_KEEP_BIN=true ;;
    esac
done

# ── Хелперы ───────────────────────────────────────────────────────────────────

info() { echo "  [·] $*"; }
ok()   { echo "  [✓] $*"; }
skip() { echo "  [–] $*"; }
die()  { echo "  [✗] $*" >&2; exit 1; }

need_root() { [[ "$(id -u)" -eq 0 ]] || die "Нужен root: sudo bash $0"; }

remove_if_exists() {
    local path="$1" desc="$2"
    if [[ -e "$path" ]]; then
        rm -rf "$path"
        ok "Удалено: ${path} (${desc})"
    else
        skip "Не найдено: ${path}"
    fi
}

# ── Предупреждение ────────────────────────────────────────────────────────────

warn_user() {
    echo
    echo "  ┌─────────────────────────────────────────────────────┐"
    echo "  │  xray-lab uninstall                                  │"
    echo "  │                                                      │"
    echo "  │  Будет удалено:                                      │"
    echo "  │    • systemd-юнит xray-lab                           │"
    echo "  │    • бинарник /usr/local/bin/xray                    │"
    echo "  │    • конфиги /usr/local/etc/xray/                   │"
    echo "  │    • геобазы /usr/local/share/xray/                 │"
    echo "  │    • логи /var/log/xray/                            │"
    echo "  │    • временные файлы /tmp/xray-lab-*/               │"
    echo "  │                                                      │"
    echo "  │  vars.env и notes/ НЕ удаляются (твои данные).      │"
    echo "  └─────────────────────────────────────────────────────┘"
    echo

    if ! $OPT_FORCE; then
        read -r -p "  Продолжить? [y/N] " reply
        [[ "$reply" =~ ^[Yy]$ ]] || { echo "  Отменено."; exit 0; }
    fi
    echo
}

# ── Остановка службы ─────────────────────────────────────────────────────────

stop_service() {
    if systemctl is-active --quiet xray-lab 2>/dev/null; then
        info "Останавливаем xray-lab..."
        systemctl stop xray-lab
        ok "Служба остановлена"
    fi
    if systemctl is-enabled --quiet xray-lab 2>/dev/null; then
        systemctl disable xray-lab 2>/dev/null || true
        ok "Служба отключена из автозапуска"
    fi
}

# ── Удаление юнита ───────────────────────────────────────────────────────────

remove_service() {
    remove_if_exists "$SYSTEMD_UNIT" "systemd unit"
    systemctl daemon-reload 2>/dev/null || true
    ok "systemd перезагружен"
}

# ── Удаление бинарника ───────────────────────────────────────────────────────

remove_binary() {
    if $OPT_KEEP_BIN; then
        skip "Бинарник сохранён (--keep-bin)"
        return
    fi

    # Снимаем capability перед удалением (чисто)
    setcap -r "$XRAY_BIN" 2>/dev/null || true
    remove_if_exists "$XRAY_BIN"      "xray binary"
    remove_if_exists "$XRAY_BIN_PREV" "xray backup binary"
}

# ── Удаление данных ──────────────────────────────────────────────────────────

remove_data() {
    remove_if_exists "$XRAY_CONF_DIR" "конфиги"
    remove_if_exists "$XRAY_DAT_DIR"  "геобазы"
    remove_if_exists "$XRAY_LOG_DIR"  "логи"
    remove_if_exists "$TMP_DIR"       "временные файлы"
}

# ── Итог ─────────────────────────────────────────────────────────────────────

print_summary() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Удаление завершено."
    echo
    echo "  Не тронуто (твои данные):"
    echo "    scenarios/*/vars.env   — секреты"
    echo "    notes/                 — дневник экспериментов"
    echo
    if $OPT_KEEP_BIN; then
        echo "  Бинарник xray сохранён (--keep-bin)."
        echo
    fi
    echo "  Для повторной установки:"
    echo "    sudo bash scripts/install.sh"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Main ─────────────────────────────────────────────────────────────────────

need_root
warn_user
stop_service
remove_service
remove_binary
remove_data
print_summary
