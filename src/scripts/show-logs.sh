#!/bin/bash
# FIXME fix script
# Просмотр логов пользовательских сервисов

# Функция показа логов пользователя
show_user_logs() {
    local username=$1
    local service_filter=$2
    local lines=${3:-50}

    if ! id "$username" &>/dev/null; then
        echo "Error: User $username does not exist"
        return 1
    fi

    local uid=$(id -u "$username")

    echo "=== Logs for user: $username (UID: $uid) ==="
    echo ""

    # Проверяем доступность журнала пользователя
    if ! sudo -u "$username"
            XDG_RUNTIME_DIR="/run/user/$uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            journalctl --user --quiet 2>/dev/null; then
        echo "User's systemd journal is not available."
        echo "The user may not have active sessions or linger enabled."

        # Показываем системные логи связанные с пользователем
        echo ""
        echo "System logs containing references to user $username:"
        journalctl _UID=$uid --lines=$lines --no-pager 2>/dev/null || \
            echo "No system logs found for UID $uid"

        return
    fi
}

# Функция поиска по логам
search_logs() {
    local username=$1
    local search_term=$2
    local lines=${3:-100}

    echo "=== Searching logs for '$search_term' in user: $username ==="
    echo ""

    # Ищем в user journal
    sudo -u "$username"
        XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        journalctl --user --lines=$lines --no-pager --grep="$search_term" 2>/dev/null || \
        echo "No matches found in user journal"
}

# Основная логика
main() {
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <username> ['all'|'search'] [lines|search_term]"
        echo ""
        echo "Examples:"
        echo "  $0 john                      # Show all logs for john (50 lines)"
        echo "  $0 john all 200              # Show all logs (200 lines)"
        echo "  $0 john search 'error'       # Search for 'error' in logs"
        return 1
    fi

    local username=$1
    local service=${2:-all}
    local param=${3:-50}

    if [ "$service" = "search" ]; then
        if [ -z "$param" ]; then
            echo "Error: Search term required for 'search' action"
            return 1
        fi
        search_logs "$username" "$param" 100
    else
        show_user_logs "$username" "$service" "$param"
    fi
}

# Проверяем что запущено от root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    return 1
fi

main "$@"
