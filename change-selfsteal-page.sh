#!/usr/bin/env bash
set -Eeuo pipefail

HTML_DIR="/opt/html"
HTML_FILE="${HTML_DIR}/index.html"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Запустите скрипт от root:"
    echo "sudo ./change-selfsteal-page.sh"
    exit 1
fi

echo "Вставьте HTML-код."
echo "После вставки нажмите Enter, затем Ctrl+D для завершения."
echo

TMP_FILE="$(mktemp)"
trap 'rm -f "${TMP_FILE}"' EXIT

# Читаем всё до Ctrl+D (EOF). || true — чтобы EOF не валил скрипт из-за set -e
while IFS= read -r line; do
    printf '%s\n' "${line}" >> "${TMP_FILE}"
done || true

# Если ничего не вставили — не перезаписываем существующий файл
if [[ ! -s "${TMP_FILE}" ]]; then
    echo
    echo "Пустой ввод — файл не изменён."
    exit 1
fi

mv "${TMP_FILE}" "${HTML_FILE}"

echo
echo "HTML-заглушка записана: ${HTML_FILE}"
echo "Перезапуск Docker-контейнера не требуется."
