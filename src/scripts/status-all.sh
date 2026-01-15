#!/bin/bash
# Просмотр статуса сервисов всех пользователей

CONFIG_FILE="/etc/user-services/config"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" || {
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
}

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

    local codeserver_port=$(echo "$port_info" | cut -d: -f2)

    # Проверяем наличие конфигов (теперь с суффиксом .username)
    local has_systemd=""
    if [ -f "$SYSTEMD_USER_DIR/code-server@$username.service" ]; then
        has_systemd="✓"
    else
        has_systemd="✗"
    fi

    # Проверяем активность сервисов (если пользователь онлайн)
    local linger_status=""
    if loginctl show-user "$username" 2>/dev/null | grep -q "Linger=yes"; then
        linger_status="✓"

        # Проверяем статусы через systemd
        local codeserver_status="?"

        if timeout 2 sudo -u "$username" systemctl --user is-active "code-server@$username.service" &>/dev/null; then
            codeserver_status="✓"
        else
            codeserver_status="✗"
        fi

        echo "$username (UID:$uid) | Ports: HTTP: CS:$codeserver_port | Configs: systemd:$has_systemd | Services: CS:$codeserver_status | Linger:$linger_status"
    else
        echo "$username (UID:$uid) | Ports: HTTP: CS:$codeserver_port | Configs: systemd:$has_systemd | Linger:$linger_status"
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
        while IFS=: read -r uid codeserver_port uname; do
            if ss -tuln | grep -q ":$codeserver_port\b"; then
                echo "  Port $codeserver_port: $uname (UID:$uid) - ACTIVE"
            fi
        done < "$PORTS_DB"
    fi
}

main "$@"
