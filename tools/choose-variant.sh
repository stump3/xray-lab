#!/usr/bin/env bash
# choose-variant.sh — интерактивный выбор варианта развёртывания
# Использование:
#   bash tools/choose-variant.sh            — выводит имя варианта на stdout
#   VAR=$(bash tools/choose-variant.sh)     — захватить в переменную
#   make choose                             — выбрать + сразу запустить init
set -euo pipefail

# ── ANSI коды ─────────────────────────────────────────────────────────────────

ESC=$'\033'
BOLD="${ESC}[1m"
DIM="${ESC}[2m"
RESET="${ESC}[0m"
GREEN="${ESC}[32m"
GRAY="${ESC}[90m"
CYAN="${ESC}[36m"
WHITE="${ESC}[97m"
BG_SEL="${ESC}[48;5;235m"   # тёмно-серый фон выделенного пункта
CLR_EOL="${ESC}[K"           # очистить до конца строки

hide_cursor() { printf '%s' "${ESC}[?25l" > /dev/tty; }
show_cursor() { printf '%s' "${ESC}[?25h" > /dev/tty; }
move_up()     { printf '%s' "${ESC}[${1}A" > /dev/tty; }

cleanup() {
    show_cursor
    # Очистить строку статуса если прерывание
    printf '\n' > /dev/tty
}
trap cleanup EXIT INT TERM

# ── Варианты: "id|Заголовок|Однострочное описание" ────────────────────────────
# Описание намеренно короткое — умещается в одну строку в любом терминале 80+

declare -a IDS TITLES DESCS
IDS=(   "variant-a" "variant-b" "variant-c" "variant-c2" "variant-d" )
TITLES=(
    "VLESS + XHTTP + Reality"
    "Nginx stream SNI routing"
    "Xray native fallbacks  (All-in-One)"
    "All-in-One расширенный  (17 протоколов)"
    "Self-SNI"
)
DESCS=(
    "Нет домена и сертификата. Xray напрямую на :443. Максимальная скрытность от DPI."
    "Reality и WS/CDN одновременно на :443. Нужны домен + сертификат + nginx-full."
    "VLESS+TLS с деревом fallbacks: много протоколов на :443. Нужны домен + сертификат."
    "VLESS/VMess/Trojan/SS × TCP/WS/gRPC/H2 на :443. Нужен wildcard сертификат + /dev/shm."
    "Decoy — собственный сайт на том же IP. Домен + IP + сертификат + сайт согласованы."
)

N=${#IDS[@]}
SEL=0   # текущий выбранный индекс

# ── Отрисовка меню ────────────────────────────────────────────────────────────

# Высота одного пункта (строк): заголовок + описание + пустая строка
ITEM_LINES=3

render() {
    for i in $(seq 0 $(( N - 1 ))); do
        if (( i == SEL )); then
            # Выделенный пункт: зелёный bullet, жирный белый заголовок, подсветка фона
            printf "${BG_SEL}  ${GREEN}${BOLD}●${RESET}${BG_SEL} ${WHITE}${BOLD}%-4s${RESET}${BG_SEL}${WHITE}${BOLD}  ${TITLES[$i]}${RESET}${CLR_EOL}\n" \
                "${IDS[$i]}" > /dev/tty
            printf "${BG_SEL}     ${CYAN}${DESCS[$i]}${RESET}${CLR_EOL}\n" > /dev/tty
        else
            # Невыделенный: серый bullet, обычный текст
            printf "  ${GRAY}○${RESET} %-4s  ${BOLD}${TITLES[$i]}${RESET}\n" \
                "${IDS[$i]}" > /dev/tty
            printf "     ${DIM}${GRAY}${DESCS[$i]}${RESET}\n" > /dev/tty
        fi
        printf '\n' > /dev/tty   # пустая строка между пунктами
    done
    printf "  ${DIM}↑↓ навигация   Enter выбор   q отмена${RESET}\n" > /dev/tty
}

# Перерисовать меню на месте (без очистки экрана)
redraw() {
    # Переместиться в начало блока меню:
    # N пунктов × ITEM_LINES строк + строка подсказки = N*ITEM_LINES + 1
    local total=$(( N * ITEM_LINES + 1 ))
    move_up "$total"
    render
}

# ── Чтение одной клавиши ──────────────────────────────────────────────────────

read_key() {
    local key
    IFS= read -r -s -n1 key < /dev/tty
    # Стрелки приходят как ESC [ A / ESC [ B
    if [[ "$key" == $'\033' ]]; then
        local seq1 seq2
        IFS= read -r -s -n1 -t 0.1 seq1 < /dev/tty || seq1=""
        IFS= read -r -s -n1 -t 0.1 seq2 < /dev/tty || seq2=""
        key="${key}${seq1}${seq2}"
    fi
    printf '%s' "$key"
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    # Проверяем что stdout — не терминал (захват в переменную): вывод только на /dev/tty
    # Результат (имя варианта) пишем в stdout в самом конце

    printf '\n' > /dev/tty
    printf "  ${BOLD}Выбери вариант развёртывания${RESET}\n" > /dev/tty
    printf "  ${DIM}──────────────────────────────────────────────────────────────${RESET}\n" > /dev/tty
    printf '\n' > /dev/tty

    hide_cursor
    render   # первая отрисовка

    while true; do
        key=$(read_key)
        case "$key" in
            $'\033[A' | k)   # стрелка вверх или k
                SEL=$(( (SEL - 1 + N) % N ))
                redraw
                ;;
            $'\033[B' | j)   # стрелка вниз или j
                SEL=$(( (SEL + 1) % N ))
                redraw
                ;;
            $'\r' | $'\n' | '')  # Enter
                show_cursor
                printf '\n' > /dev/tty
                printf "  ${GREEN}${BOLD}✓${RESET}  ${BOLD}${TITLES[$SEL]}${RESET}  ${DIM}(${IDS[$SEL]})${RESET}\n\n" > /dev/tty
                # Единственный вывод в stdout — имя варианта для захвата
                printf '%s' "${IDS[$SEL]}"
                exit 0
                ;;
            q | Q | $'\x03')  # q или Ctrl+C
                show_cursor
                printf '\n  Отменено.\n\n' > /dev/tty
                exit 1
                ;;
        esac
    done
}

main
