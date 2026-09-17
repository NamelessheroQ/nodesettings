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

# Убираем пробелы, переводы строк и управляющие символы
ANSWER="$(printf '%s' "${ANSWER}" | tr -d '[:space:]' | tr -cd '[:alnum:]')"

# Разрешаем ввод вроде y, Y или случайный символ перед y
if [[ "${ANSWER,,}" != *y* ]]; then
    echo "Изменение отменено."
    exit 0
fi

echo
echo "Вставьте HTML-код."
echo "После вставки нажмите Enter, затем Ctrl+D для завершения."
echo

TMP_FILE="$(mktemp)"

# Читаем HTML до Ctrl+D
while IFS= read -r line; do
    printf '%s\n' "${line}" >> "${TMP_FILE}"
done

mv "${TMP_FILE}" "${HTML_FILE}"

echo
echo "HTML-заглушка полностью заменена:"
echo "${HTML_FILE}"
echo
echo "Перезапуск Docker-контейнера не требуется."
