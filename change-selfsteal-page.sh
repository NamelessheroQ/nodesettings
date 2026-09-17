#!/usr/bin/env bash
set -Eeuo pipefail

HTML_DIR="/opt/html"
HTML_FILE="${HTML_DIR}/index.html"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Запустите скрипт от root:"
    echo "sudo ./change-selfsteal-page.sh"
    exit 1
fi

mkdir -p "${HTML_DIR}"

# read с "|| true" — иначе Ctrl+D убьёт скрипт из-за set -e
read -r -p "Заменить текущую HTML-заглушку? [y/N]: " ANSWER || ANSWER=""

# Простое сопоставление по шаблону, как в примере
case "${ANSWER}" in
    [Yy]*) ;;                                   # подтверждение — идём дальше
    *)                                          # всё остальное (n, N, пусто, мусор)
        echo "Изменение отменено."
        exit 0
        ;;
esac

echo
echo "Вставьте HTML-код."
echo "После вставки нажмите Enter, затем Ctrl+D для завершения."
echo

TMP_FILE="$(mktemp)"
trap 'rm -f "${TMP_FILE}"' EXIT

# Читаем HTML до Ctrl+D. || true — чтобы Ctrl+D (EOF) не валил скрипт
while IFS= read -r line; do
    printf '%s\n' "${line}" >> "${TMP_FILE}"
done || true

mv "${TMP_FILE}" "${HTML_FILE}"

echo
echo "HTML-заглушка полностью заменена:"
echo "${HTML_FILE}"
echo
echo "Перезапуск Docker-контейнера не требуется."
