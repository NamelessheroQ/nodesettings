#!/usr/bin/env bash
set -Eeuo pipefail

HTML_DIR="/opt/html"
HTML_FILE="${HTML_DIR}/index.html"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Запустите скрипт от root:"
    echo "sudo ./change-selfsteal-page.sh"
    exit 1
fi

if ! command -v nano >/dev/null 2>&1; then
    echo "nano не установлен."
    echo "Установить его можно командой:"
    echo "apt update && apt install -y nano"
    exit 1
fi

echo "Текущий файл заглушки: ${HTML_FILE}"
echo
read -r -p "Вставить или изменить HTML-заглушку? [y/N]: " ANSWER

if [[ ! "${ANSWER}" =~ ^[YyДд]$ ]]; then
    echo "Изменение отменено."
    exit 0
fi

BACKUP_FILE="${HTML_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
cp -a "${HTML_FILE}" "${BACKUP_FILE}"

echo
echo "Резервная копия создана:"
echo "${BACKUP_FILE}"
echo
echo "Откроется nano."
echo "Вставьте HTML-код, затем сохраните:"
echo "  Ctrl+O → Enter"
echo "Выйдите:"
echo "  Ctrl+X"
echo

nano "${HTML_FILE}"

echo
echo "HTML-заглушка обновлена:"
echo "${HTML_FILE}"
echo
echo "Первые строки нового файла:"
head -n 10 "${HTML_FILE}"
echo
echo "Перезапуск Docker-контейнера не требуется."
echo "Файл подключён в контейнер через volume и уже должен использоваться Caddy."
