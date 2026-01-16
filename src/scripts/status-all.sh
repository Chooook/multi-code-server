#!/bin/bash
# Просмотр статуса сервисов всех пользователей

check_user_status() {
    local username=$1
    local uid=$2

    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
    XDG_RUNTIME_DIR="/run/user/$uid"

    # Проверяем наличие конфигов (теперь с суффиксом .username)
    local has_systemd=""
    if [ -f "/home/$username/.config/systemd/user/code-server.service" ]; then
        has_systemd="✓"
    else
        has_systemd="✗"
    fi

    # Проверяем активность сервисов (если пользователь онлайн)
    local linger_status=""
    if loginctl show-user "$username" 2>/dev/null | grep -q "Linger=yes"; then
        linger_status="✓"

        # Проверяем статусы через systemd
        local code_server_status="?"

        if timeout 2 sudo -u "$username" systemctl --user is-active "code-server.service" &>/dev/null; then
            code_server_status="✓"
        else
            code_server_status="✗"
        fi

        echo "$username (UID:$uid) | Configs: systemd:$has_systemd | Services: CS:$code_server_status | Linger:$linger_status"
    else
        echo "$username (UID:$uid) | Configs: systemd:$has_systemd | Linger:$linger_status"
    fi
}

# Основная логика
main() {
    echo "=== User Services Status Report ==="
    echo "Generated: $(date)"
    echo ""
    echo "Legend: ✓=OK ✗=Not OK ◐=Partial ?=Unknown"
    echo ""
    printf "%-20s | %-25s | %-25s | %-20s\n" "User (UID)" "Ports (HTTP/code-server)" "Configurations" "Services Status"
    printf "%s\n" "----------------------------------------------------------------------------------------------------------------"

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
}

main "$@"
