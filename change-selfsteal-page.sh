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

read -r -p "Заменить текущую HTML-заглушку? [y/N]: " ANSWER

if [[ ! "${ANSWER}" =~ ^[YyДд]$ ]]; then
    echo "Изменение отменено."
    exit 0
fi

echo
echo "Вставьте HTML-код."
echo "Для завершения вставки на новой строке напишите:"
echo "END_HTML"
echo

TMP_FILE="$(mktemp)"

while IFS= read -r line; do
    [[ "${line}" == "END_HTML" ]] && break
    printf '%s\n' "${line}" >> "${TMP_FILE}"
done

mv "${TMP_FILE}" "${HTML_FILE}"

echo
echo "HTML-заглушка полностью заменена:"
echo "${HTML_FILE}"
echo
echo "Перезапуск Docker-контейнера не требуется."
