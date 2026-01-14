#!/bin/bash
# Полная очистка конфигураций и остановка сервисов пользователя

CONFIG_FILE="/etc/user-services/config"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" || {
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
}

# Функция очистки пользователя по имени
cleanup_by_username() {
    local username=$1

    if ! id "$username" &>/dev/null; then
        echo "Error: User $username does not exist"
        return 1
    fi

    local uid=$(id -u "$username")
    echo "Cleaning up services for user: $username (UID: $uid)"

    # 1. Останавливаем и отключаем сервисы
    if sudo -u "$username" systemctl --user daemon-reload 2>/dev/null; then
        sudo -u "$username" systemctl --user stop \
            "code-server.service.$username" \
            "code-server.socket.$username" \
            "nginx-proxy.service.$username" 2>/dev/null || true

        sudo -u "$username" systemctl --user disable \
            "code-server.service.$username" \
            "code-server.socket.$username" \
            "nginx-proxy.service.$username" 2>/dev/null || true
    fi

    # 2. Удаляем systemd конфиги (теперь с суффиксом .username)
    rm -f "$SYSTEMD_USER_DIR/code-server.service.$username"
    rm -f "$SYSTEMD_USER_DIR/code-server.socket.$username"
    rm -f "$SYSTEMD_USER_DIR/nginx-proxy.service.$username"

    # 3. Удаляем конфиг nginx
    rm -f "$NGINX_CONF_DIR/$username.conf"

    # 4. Удаляем запись из базы портов
    if [ -f "$PORTS_DB" ]; then
        grep -v "^$uid:" "$PORTS_DB" > "$PORTS_DB.tmp" 2>/dev/null || true
        mv "$PORTS_DB.tmp" "$PORTS_DB" 2>/dev/null || true
    fi

    # 5. Очищаем runtime директории
    rm -rf "/run/user/$uid/code-server.sock" 2>/dev/null || true

    # 6. Очищаем ссылку на инструкцию
    rm -f "/home/$username/.user-services-guide.md" 2>/dev/null || true

    # 7. Удаляем сгенерированные конфиги (опционально, комментировать если нужно оставить)
     rm -rf "/home/$username/.config/code-server" 2>/dev/null || true
     rm -rf "/home/$username/.local/share/code-server" 2>/dev/null || true

    systemctl daemon-reload
    systemctl reload nginx 2>/dev/null || true

    echo "Cleanup completed for user: $username"
}

# Функция очистки по UID
cleanup_by_uid() {
    local uid=$1
    local username=$(getent passwd "$uid" | cut -d: -f1)

    if [ -z "$username" ]; then
        echo "Error: No user with UID $uid"
        return 1
    fi

    cleanup_by_username "$username"
}

# Основная логика
main() {
    if [ $# -ne 1 ]; then
        echo "Usage: $0 <username|uid>"
        echo "Example: $0 john"
        echo "Example: $0 1001"
        exit 1
    fi

    local target=$1

    # Определяем, это username или uid
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        cleanup_by_uid "$target"
    else
        cleanup_by_username "$target"
    fi
}

# Проверяем что запущено от root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

main "$@"
