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

# Старый хелпер — оставим на всякий случай
p() { printf '%s' "$1"; }

INSTALL_DIR="/opt/selfsteal"
HTML_DIR="/opt/html"
CONTAINER_NAME="caddy-remnawave"
DEFAULT_PORT=9443

# --- Validators ---
validate_domain() {
    local d="$1"
    [[ -n "$d" && ${#d} -le 253 ]] || return 1
    [[ "$d" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || return 1
    [[ "$d" == *.* ]] || return 1
    return 0
}

validate_port() {
    local p="$1"
    [[ -n "$p" ]] || return 1
    [[ "$p" =~ ^[0-9]+$ ]] || return 1
    LC_ALL=C grep -qP '^[\x30-\x39]+$' <<<"$p" || return 1
    (( p >= 1 && p <= 65535 )) || return 1
    return 0
}

# --- Root check ---
if [[ "${EUID}" -ne 0 ]]; then
    print_error "Запустите скрипт от root:"
    print_info  "sudo $0"
    exit 1
fi

# --- Domain ---
while true; do
    read -r -p "$(prompt 'Введите домен: ')" DOMAIN
    if validate_domain "$DOMAIN"; then
        break
    fi
    print_error "Домен может содержать только латинские буквы, цифры, точки и дефисы."
    print_info  "Русские буквы и другие символы недопустимы. Пример: de.wgvpn.fun"
done
print_success "Домен принят: ${DOMAIN}"

# --- Port ---
while true; do
    read -r -p "$(prompt "Введите порт [${DEFAULT_PORT}]: ")" PORT
    PORT="${PORT:-$DEFAULT_PORT}"
    if validate_port "$PORT"; then
        break
    fi
    print_error "Порт должен быть целым числом от 1 до 65535 (только цифры, без букв и пробелов)."
done
print_success "Порт принят: ${PORT}"

# --- Docker ---
if ! command -v docker >/dev/null 2>&1; then
    print_error "Docker не установлен."
    print_info  "Установите Docker и повторно запустите скрипт."
    exit 1
fi

if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
else
    print_error "Docker Compose не найден."
    exit 1
fi
print_success "Docker и Compose доступны."

# --- Port busy check ---
if ss -ltn "( sport = :80 or sport = :${PORT} )" 2>/dev/null | grep -q LISTEN; then
    print_warning "Порт 80 или ${PORT} уже занят."
    ss -ltnp "( sport = :80 or sport = :${PORT} )" || true
    read -r -p "$(prompt 'Продолжить? [y/N] ')" answer
    [[ "${answer}" =~ ^[Yy]$ ]] || { print_info "Отменено пользователем."; exit 1; }
fi

# --- Create dirs ---
print_info "Создание каталогов..."
mkdir -p "${INSTALL_DIR}/logs" "${HTML_DIR}"

# --- Write .env ---
cat > "${INSTALL_DIR}/.env" <<EOF
SELF_STEAL_DOMAIN=${DOMAIN}
SELF_STEAL_PORT=${PORT}
EOF

# --- Write Caddyfile ---
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

# --- Write docker-compose.yml ---
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

# --- Write index.html ---
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
print_success "Файлы конфигурации созданы."

cd "${INSTALL_DIR}"

# --- Validate compose ---
print_info "Проверка конфигурации Caddy..."
if ! "${COMPOSE_CMD[@]}" config >/dev/null; then
    print_error "Ошибка в docker-compose.yml или Caddyfile."
    exit 1
fi
print_success "Конфигурация валидна."

# --- Pull image ---
print_info "Загрузка образа Caddy..."
if ! "${COMPOSE_CMD[@]}" pull; then
    print_error "Не удалось загрузить образ Caddy."
    exit 1
fi
print_success "Образ загружен."

# --- Up ---
print_info "Запуск контейнера..."
if ! "${COMPOSE_CMD[@]}" up -d; then
    print_error "Не удалось запустить контейнер."
    exit 1
fi

sleep 3

echo
print_info "Статус контейнера:"
"${COMPOSE_CMD[@]}" ps

echo
print_info "Последние логи:"
"${COMPOSE_CMD[@]}" logs --tail=30

# --- Done ---
echo
print_success "Установка завершена."
printf '  %-10s %s\n' "Каталог:" "${INSTALL_DIR}"
printf '  %-10s %s\n' "Домен:"   "${DOMAIN}"
printf '  %-10s %s\n' "Порт:"    "${PORT}"
echo
print_info "Команды управления:"
printf '  %s\n' "cd ${INSTALL_DIR} && docker compose logs -f"
printf '  %s\n' "cd ${INSTALL_DIR} && docker compose restart"
printf '  %s\n' "cd ${INSTALL_DIR} && docker compose down"
