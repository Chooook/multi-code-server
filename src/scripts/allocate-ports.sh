#!/bin/bash
# Аллокация уникальных портов для пользователя

CONFIG_FILE="/etc/user-services/config"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" || {
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
}

# Функция проверки занятости порта
is_port_free() {
    local port=$1
    # Проверяем через ss (более быстрый)
    if ss -tuln | grep -q ":$port\b"; then
        return 1 # порт занят
    fi
    # Проверяем в нашей базе портов (чтобы не выделять один порт двум пользователям)
    if [ -f "$PORTS_DB" ] && grep -q ":$port:" "$PORTS_DB"; then
        return 1 # порт уже выделен
    fi
    return 0 # порт свободен
}

# Функция поиска свободного порта
find_free_port() {
    local base_port=$1
    local min_port=$2
    local max_port=$3
    local uid=$4

    # Пытаемся вычислить порт на основе UID
    local calculated_port=$(( base_port + (uid % 10000) ))

    # Если вычисленный порт в диапазоне и свободен
    if [ $calculated_port -ge $min_port ] && [ $calculated_port -le $max_port ] && is_port_free $calculated_port; then
        echo $calculated_port
        return 0
    fi

    # Ищем следующий свободный порт
    local port=$(( min_port > calculated_port ? min_port : calculated_port ))
    while [ $port -le $max_port ]; do
        if is_port_free $port; then
            echo $port
            return 0
        fi
        port=$((port + 1))
    done

    # Если ничего не нашли
    echo "Error: No free ports in range $min_port-$max_port" >&2
    exit 1
}

# Основная логика
main() {
    local uid=$1
    local username=$2

    if [ -z "$uid" ] || [ -z "$username" ]; then
        echo "Usage: $0 <uid> <username>"
        exit 1
    fi

    # Проверяем, может порты уже выделены
    if [ -f "$PORTS_DB" ]; then
        existing_ports=$(grep "^$uid:" "$PORTS_DB" | head -1)
        if [ -n "$existing_ports" ]; then
            echo "$existing_ports" | cut -d: -f2-3
            return 0
        fi
    fi

    # Ищем свободные порты
    nginx_port=$(find_free_port $NGINX_BASE_PORT $NGINX_PROXY_PORT_MIN $NGINX_PROXY_PORT_MAX $uid)
    codeserver_port=$(find_free_port $CODESERVER_BASE_PORT $CODESERVER_PORT_MIN $CODESERVER_PORT_MAX $uid)

    # Сохраняем в базу данных
    mkdir -p "$(dirname "$PORTS_DB")"
    echo "$uid:$nginx_port:$codeserver_port:$username" >> "$PORTS_DB"

    # Удаляем дубликаты если есть
    sort -u "$PORTS_DB" -o "$PORTS_DB.tmp"
    mv "$PORTS_DB.tmp" "$PORTS_DB"

    echo "$nginx_port:$codeserver_port"
}

main "$@"
