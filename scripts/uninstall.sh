#!/usr/bin/env bash
# uninstall.sh — полное удаление xray-lab и Xray-core
#
# Использование:
#   sudo bash scripts/uninstall.sh             — интерактивное
#   sudo bash scripts/uninstall.sh --force     — без подтверждений
#   sudo bash scripts/uninstall.sh --keep-bin  — удалить всё кроме бинарника xray
set -euo pipefail

XRAY_BIN="/usr/local/bin/xray"
XRAY_BIN_PREV="/usr/local/bin/xray.prev"
XRAY_CONF_DIR="/usr/local/etc/xray"
XRAY_DAT_DIR="/usr/local/share/xray"
XRAY_LOG_DIR="/var/log/xray"
SYSTEMD_UNIT="/etc/systemd/system/xray-lab.service"

ALL_VARIANTS=(variant-a variant-b variant-c variant-d)

OPT_FORCE=false
OPT_KEEP_BIN=false

for arg in "$@"; do
    case "$arg" in
        --force)    OPT_FORCE=true ;;
        --keep-bin) OPT_KEEP_BIN=true ;;
    esac
done

# ── Хелперы ───────────────────────────────────────────────────────────────────

BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
GREEN=$'\033[32m'; YELLOW=$'\033[33m'; GRAY=$'\033[90m'; RED=$'\033[31m'

info() { echo "  [·] $*"; }
ok()   { echo "  ${GREEN}[✓]${RESET} $*"; }
skip() { echo "  ${DIM}[–]${RESET} $*"; }
warn() { echo "  ${YELLOW}[!]${RESET} $*"; }
die()  { echo "  ${RED}[✗]${RESET} $*" >&2; exit 1; }

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

confirm() {
    # confirm "Вопрос?" → возвращает 0 (yes) или 1 (no)
    # В --force режиме всегда yes
    $OPT_FORCE && return 0
    local prompt="$1"
    printf "  %s [y/N] " "$prompt"
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# ── Определяем установленные варианты ─────────────────────────────────────────

# Репо лежит на уровень выше scripts/
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

find_active_variants() {
    local active=()
    for v in "${ALL_VARIANTS[@]}"; do
        local vars_file="${REPO_ROOT}/scenarios/${v}/vars.env"
        local tmp_dir="/tmp/xray-lab-${v}"
        local pid_file="${tmp_dir}/xray.pid"
        # Считаем вариант «установленным» если есть vars.env
        [[ -f "$vars_file" ]] && active+=("$v")
    done
    printf '%s\n' "${active[@]}"
}

variant_is_running() {
    local v="$1"
    local pid_file="/tmp/xray-lab-${v}/xray.pid"
    [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null
}

# ── Стартовый экран ───────────────────────────────────────────────────────────

show_header() {
    echo
    echo "  ${BOLD}xray-lab uninstall${RESET}"
    echo "  ──────────────────────────────────────────────"

    # Показываем какие варианты есть
    local active
    mapfile -t active < <(find_active_variants)

    if [[ ${#active[@]} -gt 0 ]]; then
        echo
        echo "  Установленные варианты:"
        for v in "${active[@]}"; do
            local status="${DIM}${GRAY}остановлен${RESET}"
            variant_is_running "$v" && status="${GREEN}работает${RESET}"
            echo "    ${BOLD}${v}${RESET}  ${status}"
        done
    else
        echo
        echo "  Установленных вариантов не найдено."
    fi

    echo
    echo "  Системные компоненты:"
    [[ -f "$XRAY_BIN" ]]     && echo "    xray binary     ${XRAY_BIN}" \
                              || echo "    xray binary     ${DIM}не найден${RESET}"
    [[ -f "$SYSTEMD_UNIT" ]] && echo "    systemd unit    ${SYSTEMD_UNIT}" \
                              || echo "    systemd unit    ${DIM}не найден${RESET}"
    [[ -d "$XRAY_LOG_DIR" ]] && echo "    логи            ${XRAY_LOG_DIR}" \
                              || echo "    логи            ${DIM}не найдены${RESET}"
    echo
}

# ── Остановка и удаление вариантов ───────────────────────────────────────────

remove_variants() {
    local active
    mapfile -t active < <(find_active_variants)

    [[ ${#active[@]} -eq 0 ]] && return

    echo
    echo "  ${BOLD}Варианты${RESET}"
    echo "  ──────────────────────────────────────────────"

    for v in "${active[@]}"; do
        local vars_file="${REPO_ROOT}/scenarios/${v}/vars.env"
        local tmp_dir="/tmp/xray-lab-${v}"
        local pid_file="${tmp_dir}/xray.pid"
        local sock_file="${tmp_dir}/nginx.pid"

        echo
        echo "  ${BOLD}${v}${RESET}"

        # Показываем что есть
        variant_is_running "$v" && warn "${v}: процесс xray запущен"
        [[ -f "$vars_file" ]] && info "vars.env: ${vars_file}"

        if confirm "Остановить и удалить ${v}?"; then
            # Остановить xray
            if [[ -f "$pid_file" ]]; then
                local pid
                pid=$(cat "$pid_file")
                kill "$pid" 2>/dev/null && ok "${v}: xray остановлен (pid ${pid})" || true
                rm -f "$pid_file"
            fi

            # Остановить nginx этого варианта
            local nginx_pid_file="${tmp_dir}/nginx.pid"
            if [[ -f "$nginx_pid_file" ]]; then
                local npid
                npid=$(cat "$nginx_pid_file")
                kill "$npid" 2>/dev/null && ok "${v}: nginx остановлен (pid ${npid})" || true
            fi

            # Удалить unix socket если есть (variant-c)
            local sock="/dev/shm/xraylab-c-h1.sock"
            [[ -S "$sock" ]] && rm -f "$sock" && ok "Удалён unix socket: ${sock}" || true

            # Удалить tmp
            remove_if_exists "$tmp_dir" "временные файлы ${v}"

            # vars.env — спрашиваем отдельно (там UUID, ключи)
            if [[ -f "$vars_file" ]]; then
                if confirm "  Удалить vars.env ${v} (UUID и ключи будут утеряны)?"; then
                    rm -f "$vars_file"
                    ok "Удалён: ${vars_file}"
                else
                    skip "Сохранён: ${vars_file}"
                fi
            fi
        else
            skip "${v}: пропущен"
        fi
    done
}

# ── Системные компоненты ──────────────────────────────────────────────────────

stop_service() {
    if systemctl is-active --quiet xray-lab 2>/dev/null; then
        info "Останавливаем xray-lab service..."
        systemctl stop xray-lab
        ok "Служба остановлена"
    fi
    if systemctl is-enabled --quiet xray-lab 2>/dev/null; then
        systemctl disable xray-lab 2>/dev/null || true
        ok "Служба отключена из автозапуска"
    fi
}

remove_system() {
    echo
    echo "  ${BOLD}Системные компоненты${RESET}"
    echo "  ──────────────────────────────────────────────"

    if confirm "Удалить systemd-юнит, бинарник, конфиги, геобазы и логи?"; then
        stop_service

        remove_if_exists "$SYSTEMD_UNIT" "systemd unit"
        systemctl daemon-reload 2>/dev/null || true

        if $OPT_KEEP_BIN; then
            skip "Бинарник сохранён (--keep-bin)"
        else
            setcap -r "$XRAY_BIN" 2>/dev/null || true
            remove_if_exists "$XRAY_BIN"      "xray binary"
            remove_if_exists "$XRAY_BIN_PREV" "xray backup binary"
        fi

        remove_if_exists "$XRAY_CONF_DIR" "конфиги"
        remove_if_exists "$XRAY_DAT_DIR"  "геобазы"
        remove_if_exists "$XRAY_LOG_DIR"  "логи"
    else
        skip "Системные компоненты сохранены"
    fi
}

# ── Итог ─────────────────────────────────────────────────────────────────────

print_summary() {
    echo
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Готово."
    echo
    echo "  Не тронуто (если не подтвердил удаление):"
    echo "    scenarios/*/vars.env   — UUID и ключи"
    echo "    notes/                 — дневник экспериментов"
    echo
    echo "  Для повторной установки:"
    echo "    sudo bash scripts/install.sh"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Main ─────────────────────────────────────────────────────────────────────

need_root
show_header

if ! $OPT_FORCE; then
    confirm "Начать удаление?" || { echo "  Отменено."; exit 0; }
fi

remove_variants
remove_system
print_summary
