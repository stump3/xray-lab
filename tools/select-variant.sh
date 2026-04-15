#!/usr/bin/env bash
# select-variant.sh — интерактивный выбор варианта развёртывания
# Вывод: имя выбранного варианта (например "variant-b") в stdout
# Всё остальное — в /dev/tty (не мешает подстановке в переменную)
#
# Использование:
#   VAR=$(bash tools/select-variant.sh)
#   bash tools/select-variant.sh --write   # пишет VAR= в /tmp/xray-lab-selected-variant
set -euo pipefail

# ── Описания вариантов ─────────────────────────────────────────────────────────

declare -a NAMES=(
    "Variant A  — VLESS + XHTTP + Reality"
    "Variant B  — Nginx stream SNI routing"
    "Variant C  — Xray native fallbacks (All-in-One)"
    "Variant C2 — All-in-One, 17 протоколов"
    "Variant D  — Self-SNI: собственный decoy-сайт"
)

declare -a KEYS=(
    "variant-a"
    "variant-b"
    "variant-c"
    "variant-c2"
    "variant-d"
)

declare -a DESCS=(
    "Xray напрямую на :443. Домен и сертификат не нужны.\nМаксимальная скрытность — Reality с decoy microsoft.com."
    "Nginx stream на :443 читает SNI и роутит: Reality-клиенты → Xray,\nосвоенный домен → Nginx HTTPS + WS. Нужен домен и сертификат."
    "Xray на :443 терминирует TLS и раздаёт протоколы через fallbacks:\nVLESS+WS, VMess+WS, decoy-сайт. Reality недоступна. Нужен домен."
    "Полный All-in-One: VLESS+Vision+TLS → fallbacks → 17 протоколов.\nVLESS/VMess/Trojan/SS × TCP/WS/gRPC/H2. Нужен wildcard сертификат."
    "Xray на :443 с собственным сертификатом. Decoy — настоящий сайт\nна том же IP. Домен, сертификат и IP согласованы. Reality недоступна."
)

declare -a REQS=(
    "Без домена  ·  Без сертификата  ·  Низкая сложность"
    "Домен + сертификат  ·  nginx-full (stream)  ·  Средняя сложность"
    "Домен + сертификат  ·  /dev/shm  ·  Высокая сложность"
    "Wildcard сертификат  ·  /dev/shm  ·  Nginx http_v2  ·  Очень высокая сложность"
    "Домен + сертификат  ·  Низкая сложность"
)

COUNT=${#NAMES[@]}

# ── ANSI хелперы ──────────────────────────────────────────────────────────────

ESC=$'\033'
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"
FG_CYAN="${ESC}[36m"
FG_WHITE="${ESC}[97m"
FG_GRAY="${ESC}[90m"    # тёмно-серый для описания
BG_SEL="${ESC}[48;5;236m"   # очень тёмный фон для выбранного

CURSOR_HIDE="${ESC}[?25l"
CURSOR_SHOW="${ESC}[?25h"
CLEAR_LINE="${ESC}[2K"
MOVE_UP="${ESC}[A"

tty_print() { printf "%s" "$*" > /dev/tty; }
tty_println() { printf "%s\n" "$*" > /dev/tty; }

# ── Рендер ────────────────────────────────────────────────────────────────────

# Высота одного item в строках (для правильного перемещения курсора вверх)
ITEM_LINES=4   # имя + строка описания 1 + строка описания 2 + требования + пустая

render_item() {
    local idx=$1
    local selected=$2   # 0 или 1

    local name="${NAMES[$idx]}"
    local desc="${DESCS[$idx]}"
    local req="${REQS[$idx]}"

    # Разбиваем desc по \n
    local line1 line2
    line1=$(printf "%b" "$desc" | head -1)
    line2=$(printf "%b" "$desc" | tail -1)

    if (( selected )); then
        # Выбранный: стрелка + cyan имя + dim описание
        tty_print "${CLEAR_LINE}  ${BOLD}${FG_CYAN}❯  ${name}${RESET}\n"
        tty_print "${CLEAR_LINE}     ${FG_GRAY}${line1}${RESET}\n"
        tty_print "${CLEAR_LINE}     ${FG_GRAY}${line2}${RESET}\n"
        tty_print "${CLEAR_LINE}     ${DIM}${req}${RESET}\n"
    else
        # Невыбранный: отступ + dim имя + ещё более dim описание
        tty_print "${CLEAR_LINE}     ${DIM}${name}${RESET}\n"
        tty_print "${CLEAR_LINE}\n"
        tty_print "${CLEAR_LINE}\n"
        tty_print "${CLEAR_LINE}\n"
    fi
    tty_print "${CLEAR_LINE}\n"   # пустая строка между items
}

render_all() {
    local sel=$1
    for (( i=0; i<COUNT; i++ )); do
        render_item "$i" "$(( i == sel ? 1 : 0 ))"
    done
}

# Общее количество строк которое рисуем (для перемотки вверх)
TOTAL_LINES=$(( COUNT * (ITEM_LINES + 1) ))

move_to_top() {
    for (( i=0; i<TOTAL_LINES; i++ )); do
        tty_print "${MOVE_UP}"
    done
}

# ── Чтение клавиш ─────────────────────────────────────────────────────────────

read_key() {
    local key seq
    IFS= read -r -s -n1 key < /dev/tty
    if [[ "$key" == $'\x1b' ]]; then
        IFS= read -r -s -n2 -t 0.05 seq < /dev/tty || seq=""
        case "$seq" in
            "[A") echo "UP"   ;;
            "[B") echo "DOWN" ;;
            *)    echo "ESC"  ;;
        esac
    elif [[ "$key" == "" || "$key" == $'\n' || "$key" == $'\r' ]]; then
        echo "ENTER"
    elif [[ "$key" == "q" || "$key" == "Q" ]]; then
        echo "QUIT"
    elif [[ "$key" == "k" || "$key" == "K" ]]; then
        echo "UP"
    elif [[ "$key" == "j" || "$key" == "J" ]]; then
        echo "DOWN"
    else
        echo "OTHER"
    fi
}

# ── Cleanup при выходе ────────────────────────────────────────────────────────

cleanup() {
    tty_print "${CURSOR_SHOW}"
    # Восстановить нормальный режим терминала
    stty sane 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    local selected=0

    tty_println ""
    tty_print "  ${BOLD}Выбери вариант развёртывания${RESET}  "
    tty_println "${DIM}(↑↓ или j/k для навигации, Enter для выбора)${RESET}"
    tty_println ""

    # Скрываем курсор и рендерим первый раз
    tty_print "${CURSOR_HIDE}"
    render_all "$selected"

    while true; do
        local key
        key=$(read_key)

        case "$key" in
            UP)
                (( selected > 0 )) && (( selected-- ))
                ;;
            DOWN)
                (( selected < COUNT - 1 )) && (( selected++ ))
                ;;
            ENTER)
                break
                ;;
            QUIT | ESC)
                tty_println ""
                tty_println "  Отменено."
                exit 1
                ;;
        esac

        move_to_top
        render_all "$selected"
    done

    tty_print "${CURSOR_SHOW}"

    # Финальный вывод — показываем что выбрали
    tty_println ""
    tty_println "  ${BOLD}${FG_CYAN}✓${RESET}  ${BOLD}${NAMES[$selected]}${RESET}"
    tty_println ""

    local chosen="${KEYS[$selected]}"

    if [[ "${1:-}" == "--write" ]]; then
        echo "$chosen" > /tmp/xray-lab-selected-variant
    else
        # Выводим только ключ в stdout — для подстановки VAR=$(...)
        echo "$chosen"
    fi
}

main "${1:-}"
