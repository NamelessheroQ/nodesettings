#!/usr/bin/env bash
set -Eeuo pipefail

# --- Colors ---
if command -v tput >/dev/null 2>&1 && tput setaf 1 >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW="$(tput bold)$(tput setaf 3)"
    BLUE=$(tput setaf 4)
    PURPLE=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    NC=$(tput sgr0)
else
    RED=$'\e[0;31m'
    GREEN=$'\e[0;32m'
    YELLOW=$'\e[1;33m'
    BLUE=$'\e[0;34m'
    PURPLE=$'\e[0;35m'
    CYAN=$'\e[0;36m'
    BOLD=$'\e[1m'
    NC=$'\e[0m'
fi

# --- Logging helpers ---
print_success() { printf '%s\n' "${GREEN}✓ $*${NC}"; }
print_error()   { printf '%s\n' "${RED}✗ $*${NC}" >&2; }
print_warning() { printf '%s\n' "${YELLOW}⚠ $*${NC}" >&2; }
print_info()    { printf '%s\n' "${PURPLE}ℹ $*${NC}"; }

# Цветное приглашение для read -p (без \n, без интерпретации % и \)
prompt() { printf '%s' "${CYAN}$*${NC}"; }

HTML_DIR="/opt/html"
HTML_FILE="${HTML_DIR}/index.html"

# --- Root check ---
if [[ "${EUID}" -ne 0 ]]; then
    print_error "Запустите скрипт от root:"
    print_info  "sudo ./change-selfsteal-page.sh"
    exit 1
fi

# --- Каталог должен существовать ---
if [[ ! -d "${HTML_DIR}" ]]; then
    print_error "Каталог ${HTML_DIR} не найден."
    print_info  "Сначала запустите install-selfsteal.sh."
    exit 1
fi

# --- Инструкции ---
print_info "Вставьте HTML-код."
print_info "После вставки нажмите Enter, затем Ctrl+D для завершения."
echo

# --- Временный файл ---
TMP_FILE="$(mktemp)"
trap 'rm -f "${TMP_FILE}"' EXIT

# Читаем всё до Ctrl+D (EOF). || true — чтобы EOF не валил скрипт из-за set -e
while IFS= read -r line; do
    printf '%s\n' "${line}" >> "${TMP_FILE}"
done || true

# Если ничего не вставили — не перезаписываем существующий файл
if [[ ! -s "${TMP_FILE}" ]]; then
    echo
    print_error "Пустой ввод — файл не изменён."
    exit 1
fi

mv "${TMP_FILE}" "${HTML_FILE}"

echo
print_success "HTML-заглушка записана: ${HTML_FILE}"
print_info    "Перезапуск Docker-контейнера не требуется."
