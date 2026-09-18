#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="/opt/selfsteal"
HTML_DIR="/opt/html"
CONTAINER_NAME="caddy-remnawave"
DEFAULT_PORT=9443

# Хелпер: вывод строки как есть, без перевода строки и без форматирования.
# Аналог `printf '%s' "$1"`, но короче читается в read -p.
p() { printf '%s' "$1"; }

validate_domain() {
    local d="$1"
    [[ -n "$d" && ${#d} -le 253 ]] || return 1
    [[ "$d" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || return 1
    [[ "$d" == *.* ]] || return 1
    return 0
}

validate_port() {
    local p="$1"
    # непусто
    [[ -n "$p" ]] || return 1
    # только ASCII-цифры, ничего больше (ни букв, ни точек, ни пробелов)
    [[ "$p" =~ ^[0-9]+$ ]] || return 1
    # на всякий случай явная проверка, что это чистая ASCII-строка
    LC_ALL=C grep -qP '^[\x30-\x39]+$' <<<"$p" || return 1
    # числовой диапазон
    (( p >= 1 && p <= 65535 )) || return 1
    return 0
}

if [[ "${EUID}" -ne 0 ]]; then
    echo "Запустите скрипт от root:"
    echo "sudo $0"
    exit 1
fi

while true; do
    read -r -p "$(printf '%s' 'Введите домен: ')" DOMAIN
    if validate_domain "$DOMAIN"; then
        break
    fi
    echo "Ошибка: домен может содержать только латинские буквы, цифры, точки и дефисы."
    echo "Русские буквы и другие символы недопустимы. Пример: de.wgvpn.fun"
done

while true; do
    read -r -p "$(printf '%s' "Введите порт [${DEFAULT_PORT}]: ")" PORT
    PORT="${PORT:-$DEFAULT_PORT}"
    if validate_port "$PORT"; then
        break
    fi
    echo "Ошибка: порт должен быть целым числом от 1 до 65535 (только цифры, без букв и пробелов)."
done

if ! command -v docker >/dev/null 2>&1; then
    echo "Ошибка: Docker не установлен."
    echo "Установите Docker и повторно запустите скрипт."
    exit 1
fi

if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
else
    echo "Ошибка: Docker Compose не найден."
    exit 1
fi

if ss -ltn "( sport = :80 or sport = :${PORT} )" 2>/dev/null | grep -q LISTEN; then
    echo "Предупреждение: порт 80 или ${PORT} уже занят."
    ss -ltnp "( sport = :80 or sport = :${PORT} )" || true
    read -r -p "$(p 'Продолжить? [y/N] ')" answer
    [[ "${answer}" =~ ^[Yy]$ ]] || exit 1
fi

echo "Создание каталогов..."
mkdir -p "${INSTALL_DIR}/logs" "${HTML_DIR}"

cat > "${INSTALL_DIR}/.env" <<EOF
SELF_STEAL_DOMAIN=${DOMAIN}
SELF_STEAL_PORT=${PORT}
EOF

cat > "${INSTALL_DIR}/Caddyfile" <<'EOF'
{
    https_port {$SELF_STEAL_PORT}
    default_bind 127.0.0.1

    servers {
        listener_wrappers {
            proxy_protocol {
                allow 127.0.0.1/32
            }
            tls
        }
    }

    auto_https disable_redirects
}

http://{$SELF_STEAL_DOMAIN} {
    bind 0.0.0.0
    redir https://{$SELF_STEAL_DOMAIN}{uri} permanent
}

https://{$SELF_STEAL_DOMAIN} {
    root * /var/www/html
    try_files {path} /index.html
    file_server
}

:{$SELF_STEAL_PORT} {
    tls internal
    respond 204
}

:80 {
    bind 0.0.0.0
    respond 204
}
EOF

cat > "${INSTALL_DIR}/docker-compose.yml" <<'EOF'
services:
  caddy:
    image: caddy:latest
    container_name: caddy-remnawave
    restart: unless-stopped
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ../html:/var/www/html:ro
      - ./logs:/var/log/caddy
      - caddy_data_selfsteal:/data
      - caddy_config_selfsteal:/config
    env_file:
      - .env
    network_mode: host

volumes:
  caddy_data_selfsteal:
  caddy_config_selfsteal:
EOF

cat > "${HTML_DIR}/index.html" <<'EOF'
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>Selfsteal</title>
</head>
<body>
    <h1>It works.</h1>
</body>
</html>
EOF

chmod 600 "${INSTALL_DIR}/.env"

echo "Проверка конфигурации Caddy..."
cd "${INSTALL_DIR}"

"${COMPOSE_CMD[@]}" config >/dev/null

echo "Загрузка образа Caddy..."
"${COMPOSE_CMD[@]}" pull

echo "Запуск контейнера..."
"${COMPOSE_CMD[@]}" up -d

sleep 3

echo
echo "Статус контейнера:"
"${COMPOSE_CMD[@]}" ps

echo
echo "Последние логи:"
"${COMPOSE_CMD[@]}" logs --tail=30

echo
echo "Установка завершена."
echo "Каталог: ${INSTALL_DIR}"
echo "Домен:   ${DOMAIN}"
echo "Порт:    ${PORT}"
echo
echo "Команды управления:"
echo "  cd ${INSTALL_DIR} && docker compose logs -f"
echo "  cd ${INSTALL_DIR} && docker compose restart"
echo "  cd ${INSTALL_DIR} && docker compose down"
