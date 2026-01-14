#!/bin/bash
# Просмотр статуса сервисов всех пользователей

CONFIG_FILE="/etc/user-services/config"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" || {
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
}

# Функция проверки активности порта
check_port_active() {
    local port=$1
    if ss -tuln | grep -q ":$port\b"; then
        echo "✓"
    else
        echo "✗"
    fi
}

# Функция проверки статуса одного пользователя
check_user_status() {
    local username=$1
    local uid=$2

    # Получаем порты из базы
    local port_info=""
    if [ -f "$PORTS_DB" ]; then
        port_info=$(grep "^$uid:" "$PORTS_DB" | head -1)
    fi

    if [ -z "$port_info" ]; then
        echo "$username (UID:$uid) | No ports allocated | No services configured"
        return
    fi

    local nginx_port=$(echo "$port_info" | cut -d: -f2)
    local codeserver_port=$(echo "$port_info" | cut -d: -f3)

    # Проверяем наличие конфигов
    local has_systemd=""
    if [ -f "$SYSTEMD_USER_DIR/code-server.service" ] &&
       [ -f "$SYSTEMD_USER_DIR/nginx-proxy.service" ]; then
        has_systemd="✓"
    else
        has_systemd="✗"
    fi

    local has_nginx=""
    if [ -f "$NGINX_CONF_DIR/$username.conf" ]; then
        has_nginx="✓"
    else
        has_nginx="✗"
    fi

    # Проверяем активность сервисов (если пользователь онлайн)
    local linger_status=""
    if loginctl show-user "$username" 2>/dev/null | grep -q "Linger=yes"; then
        linger_status="✓"

        # Проверяем статусы через systemd (если можем)
        local codeserver_status="?"
        local nginx_status="?"

        if timeout 2 sudo -u "$username" systemctl --user is-active code-server.service &>/dev/null; then
            codeserver_status="✓"
        elif timeout 2 sudo -u "$username" systemctl --user is-active code-server.socket &>/dev/null; then
            codeserver_status="◐" # сокет активен, сервис может быть остановлен
        else
            codeserver_status="✗"
        fi

        if timeout 2 sudo -u "$username" systemctl --user is-active nginx-proxy.service &>/dev/null; then
            nginx_status="✓"
        else
            nginx_status="✗"
        fi

        echo "$username (UID:$uid) | Ports: HTTP:$nginx_port/CS:$codeserver_port | Configs: systemd:$has_systemd nginx:$has_nginx | Services: CS:$codeserver_status Nginx:$nginx_status | Linger:$linger_status"
    else
        echo "$username (UID:$uid) | Ports: HTTP:$nginx_port/CS:$codeserver_port | Configs: systemd:$has_systemd nginx:$has_nginx | Linger:$linger_status"
    fi
}

# Основная логика
main() {
    echo "=== User Services Status Report ==="
    echo "Generated: $(date)"
    echo ""
    echo "Legend: ✓=OK ✗=Not OK ◐=Partial ?=Unknown"
    echo ""
    printf "%-20s | %-25s | %-25s | %-20s\n" "User (UID)" "Ports (HTTP/CodeServer)" "Configurations" "Services Status"
    printf "%s\n" "----------------------------------------------------------------------------------------------------------------"

    # Проверяем глобальный nginx
    if systemctl is-active --quiet nginx; then
        echo "Global nginx: ✓ Running"
    else
        echo "Global nginx: ✗ Not running"
    fi

    if [ -f "$PORTS_DB" ]; then
        echo "Ports database: ✓ Found ($(wc -l < "$PORTS_DB") users)"
    else
        echo "Ports database: ✗ Not found"
    fi

    echo ""

    # Проверяем всех пользователей
    getent passwd | while IFS=: read -r username _ uid _ _ home shell; do
        [ "$uid" -lt 1000 ] && continue
        [ "$username" = "nobody" ] && continue
        [ ! -d "$home" ] && continue
        [[ "$shell" == *"nologin"* ]] && continue
        [[ "$shell" == *"false"* ]] && continue

        check_user_status "$username" "$uid"
    done

    echo ""
    echo "=== Active Ports Summary ==="
    echo "HTTP proxy ports in use:"
    if [ -f "$PORTS_DB" ]; then
        while IFS=: read -r uid nginx_port codeserver_port uname; do
            if ss -tuln | grep -q ":$nginx_port\b"; then
                echo "  Port $nginx_port: $uname (UID:$uid) - ACTIVE"
            fi
        done < "$PORTS_DB"
    fi
}

main "$@"
