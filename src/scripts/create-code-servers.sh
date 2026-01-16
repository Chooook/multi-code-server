#!/bin/bash
# Скрипт создания/обновления сервисов для пользователей

EXCLUDED_USERS_DIR="/etc/auto-code-server/excluded_users"
BIN_DIR="/usr/local/bin"

# Функция проверки существования всех необходимых конфигов
check_user_configs_exist() {
    local username="$1"
    local uid="$2"

    local config_file="/home/$username/.config/systemd/user/code-server.service"
    if [ ! -f "$config_file" ]; then
        echo "Missing systemd config: $config_file"
        return 1  # Конфиг отсутствует
    fi

    local code_server_config="/home/$username/.config/code-server/config.yaml"
    if [ ! -f "$code_server_config" ]; then
        echo "Missing code-server config: $code_server_config"
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

    if [ ! -S "/run/user/$uid/bus" ]; then
        echo "User $username is not logged in yet. Skipping" && return 1;
    fi

    # Создаём конфигурационные файлы из шаблонов

    # 1. Systemd service files
    local template=code-server.service.template
    local dest="/home/$username/.config/systemd/user/code-server.service"
    mkdir -p "$(dirname "$dest")"
    sed \
        -e "s|%i|$username|g" \
        -e "s|%u|$uid|g" \
        -e "s|%CODE_SERVER_PORT%|$code_server_port|g" \
        "/etc/auto-code-server/templates/$template" > "$dest"

    chown "$username:$username" "$dest"
    chmod 644 "$dest"

    # 2. Code-server config
    local conf_template=code-server-config.yaml.template
    local config_dir="/home/$username/.config/code-server"
    mkdir -p "$config_dir"
    local code_server_config_path="$config_dir/config.yaml"

    # Генерируем случайный пароль
    local password=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-12)
    # Аллокация портов
    local code_server_port=$("$BIN_DIR/allocate-port")
    sed \
        -e "s|%UNAME%|$username|g" \
        -e "s|%CODE_SERVER_PORT%|$code_server_port|g" \
        -e "s|%PASSWORD%|$password|g" \
        "/etc/auto-code-server/templates/$conf_template" > "$code_server_config_path"

    chown "$username:$username" "$code_server_config_path"
    chmod 600 "$code_server_config_path"

    # Reload systemd
    systemctl daemon-reload

    # Enable and start services
    sudo -u "$username" \
        XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        systemctl --user daemon-reload
    sudo -u "$username" \
        XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        systemctl --user enable --now \
        "code-server.service" 2>/dev/null || true

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
        [[ "$shell" == *"evm"* ]] && continue
        # check if user excluded in file excluded_users
        if [ -e "$EXCLUDED_USERS_DIR/$username" ]; then
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
        return 0
        ;;
    --force|-f)
        main true
        ;;
    --user)
        if [ -z "$2" ]; then
            echo "Error: --user requires username"
            return 1
        fi
        username="$2"
        uid=$(id -u "$username" 2>/dev/null || echo "")
        if [ -z "$uid" ]; then
            echo "Error: User $username not found"
            return 1
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
