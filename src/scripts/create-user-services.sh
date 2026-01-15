#!/bin/bash
# Скрипт создания/обновления сервисов для пользователей

MAIN_CONFIG="/etc/user-services/config"
[ -f "$MAIN_CONFIG" ] && source "$MAIN_CONFIG" || {
    echo "Config file not found: $MAIN_CONFIG"
    exit 1
}

# Функция проверки существования всех необходимых конфигов
check_user_configs_exist() {
    local username="$1"
    local uid="$2"

    local config_file="$SYSTEMD_USER_DIR/code-server@$username.service"
    if [ ! -f "$config_file" ]; then
        echo "Missing systemd config: $config_file"
        return 1  # Конфиг отсутствует
    fi

    local codeserver_config="/home/$username/.config/code-server/config.yaml"
    if [ ! -f "$codeserver_config" ]; then
        echo "Missing code-server config: $codeserver_config"
        return 1
    fi

    if [ -f "$PORTS_DB" ]; then
        if ! grep -q "^$uid:" "$PORTS_DB"; then
            echo "Missing port allocation for UID: $uid"
            return 1
        fi
    else
        echo "Ports database not found: $PORTS_DB"
        return 1
    fi

    if ! loginctl show-user "$username" 2>/dev/null | grep -q "Linger=yes"; then
        echo "Linger not enabled for user: $username"
        return 1
    fi

    # Все конфиги существуют
    return 0
}

# Функция создания сервисов для пользователя
setup_user_services() {
    local username="$1"
    local uid="$2"

    echo "Setting up services for user: $username (UID: $uid)"

    # Включаем лингеринг
    loginctl enable-linger "$username" 2>/dev/null || true

    # Аллокация портов
    local ports
    ports=$(/etc/user-services/scripts/allocate-ports.sh "$uid" "$username")
    local codeserver_port=$(echo "$ports" | cut -d: -f1)

    # Создаём конфигурационные файлы из шаблонов

    # 1. Systemd service files
    local template = code-server@.service
    local dest_name="${template/@./@$username.}"
    local dest="$SYSTEMD_USER_DIR/$dest_name"

    sed \
        -e "s|%i|$username|g" \
        -e "s|%CODESERVER_PORT%|codeserver_port|g" \
        "$TEMPLATES_DIR/$template.template" > "$dest"

    chmod 644 "$dest"

    # 2. Code-server config
    local config_dir="/home/$username/.config/code-server"
    mkdir -p "$config_dir"
    local codeserver_config="$config_dir/config.yaml"

    # Генерируем случайный пароль и хеш
    local password=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-12)
    local password_hash=$(echo -n "$password" | sha256sum | cut -d' ' -f1)

    # Сохраняем пароль для пользователя
    local password_file="/home/$username/.code-server-password.txt"
    echo "Initial code-server password for $username: $password" > "$password_file"
    chown "$username:$username" "/home/$username/.code-server-initial-password.txt"
    chmod 600 "/home/$username/.code-server-initial-password.txt"

    cat > "$codeserver_config" << EOF
password: $password_hash
user-data-dir: /home/$username/.local/share/code-server
extensions-dir: /home/$username/.local/share/code-server/extensions
EOF
    chown "$username:$username" "$codeserver_config"
    chmod 600 "$codeserver_config"

    # Reload systemd
    systemctl daemon-reload

    # Enable and start services
    sudo -u "$username" systemctl --user daemon-reload
    sudo -u "$username" systemctl --user enable --now \
        "code-server@$username.service" 2>/dev/null || true

    echo "Services setup completed for $username"
}

# Основной цикл
main() {
    local force_update=${1:-false}

    echo "=== User Services Setup ==="
    echo "Mode: $([ "$force_update" = true ] && echo "FORCE CREATE" || echo "CHECK AND CREATE")"
    echo ""

    # Получаем список всех обычных пользователей
    getent passwd | while IFS=: read -r username _ uid _ _ home shell; do
        # Пропускаем системных пользователей и root
        [ "$uid" -lt 1000 ] && continue
        [ "$username" = "nobody" ] && continue
        [ ! -d "$home" ] && continue
        [[ "$shell" == *"nologin"* ]] && continue
        [[ "$shell" == *"false"* ]] && continue
        # check if user excluded in file excluded_users
        if grep -q "^$username$" "$EXCLUDED_USERS"; then
            echo "Skipping excluded user: $username"
            continue
        fi

        echo "Processing user: $username (UID: $uid)"

        if [ "$force_update" = true ]; then
            setup_user_services "$username" "$uid"
        else
            # Проверяем существование конфигов
            if check_user_configs_exist "$username" "$uid"; then
                echo "  ✓ All configs exist, skipping"
            else
                echo "  ✗ Missing configs, creating..."
                setup_user_services "$username" "$uid"
            fi
        fi

        echo ""
    done

    echo "=== Setup completed ==="
    echo "Total users processed: $(getent passwd | grep -c "^[^:]*:[^:]*:[1-9][0-9][0-9][0-9]")"
}

# Обработка аргументов командной строки
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help"
        echo "  --force, -f    Force update all configurations"
        echo "  --user NAME    Process only specific user"
        echo ""
        echo "Examples:"
        echo "  $0              # Check and create missing configs"
        echo "  $0 --force      # Update all existing configs"
        echo "  $0 --user john  # Process only user 'john'"
        exit 0
        ;;
    --force|-f)
        main true
        ;;
    --user)
        if [ -z "$2" ]; then
            echo "Error: --user requires username"
            exit 1
        fi
        username="$2"
        uid=$(id -u "$username" 2>/dev/null || echo "")
        if [ -z "$uid" ]; then
            echo "Error: User $username not found"
            exit 1
        fi
        # Обработка только одного пользователя
        if check_user_configs_exist "$username" "$uid"; then
            echo "All configs exist for $username"
            read -p "Create anyway? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                setup_user_services "$username" "$uid"
            fi
        else
            setup_user_services "$username" "$uid"
        fi
        ;;
    *)
        main false
        ;;
esac
