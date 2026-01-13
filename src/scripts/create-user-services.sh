#!/bin/bash
# Скрипт создания/обновления сервисов для пользователей

CONFIG_FILE="/etc/user-services/config"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" || {
    echo "Config file not found: $CONFIG_FILE"
    exit 1
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
    local nginx_port=$(echo "$ports" | cut -d: -f1)
    local codeserver_port=$(echo "$ports" | cut -d: -f2)

    # Генерируем хеш пароля если нужно
    local password_hash=""
    local config_dir="/home/$username/.config/code-server"
    local config_file="$config_dir/config.yaml"

    if [ -f "$config_file" ]; then
        # Извлекаем хеш из существующего конфига
        password_hash=$(grep '^password:' "$config_file" | head -1 | awk '{print $2}' | tr -d '[:space:]' || echo "")
    fi

    if [ -z "$password_hash" ]; then
        # Генерируем случайный пароль и хеш
        local password=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-12)
        password_hash=$(echo -n "$password" | sha256sum | cut -d' ' -f1)

        # Сохраняем пароль для пользователя
        echo "Initial code-server password for $username: $password" > "/home/$username/.code-server-initial-password.txt"
        chown "$username:$username" "/home/$username/.code-server-initial-password.txt"
        chmod 600 "/home/$username/.code-server-initial-password.txt"
    fi

    # Создаём конфигурационные файлы из шаблонов

    # 1. Systemd service files
    for template in code-server.socket code-server.service nginx-proxy.service; do
        local dest="$SYSTEMD_USER_DIR/${template//%i/$username}"

        sed \
            -e "s|%i|$username|g" \
            -e "s|%UID%|$uid|g" \
            -e "s|%PASSWORD_HASH%|$password_hash|g" \
            -e "s|%CODESERVER_PORT%|$codeserver_port|g" \
            -e "s|%NGINX_PORT%|$nginx_port|g" \
            "$TEMPLATES_DIR/$template.template" > "$dest"

        chmod 644 "$dest"
    done

    # 2. Pre-start script (будет исполняться от пользователя)
    local prestart_script="/home/$username/.config/code-server/pre-start.sh"
    sed \
        -e "s|%i|$username|g" \
        -e "s|%UID%|$uid|g" \
        -e "s|%PASSWORD_HASH%|$password_hash|g" \
        -e "s|%CODESERVER_PORT%|$codeserver_port|g" \
        "$TEMPLATES_DIR/codeserver-pre-start.sh.template" > "$prestart_script"

    chown "$username:$username" "$prestart_script"
    chmod 755 "$prestart_script"

    # 3. Environment file (будет перезаписан pre-start скриптом при запуске)
    local env_file="/home/$username/.config/code-server/environment.template"
    sed \
        -e "s|%i|$username|g" \
        -e "s|%UID%|$uid|g" \
        -e "s|%CODESERVER_PORT%|$codeserver_port|g" \
        "$TEMPLATES_DIR/codeserver.env.template" > "$env_file"

    chown "$username:$username" "$env_file"
    chmod 600 "$env_file"

    # 4. Nginx config
    local nginx_conf="$NGINX_CONF_DIR/$username.conf"
    sed \
        -e "s|%i|$username|g" \
        -e "s|%UID%|$uid|g" \
        -e "s|%NGINX_PORT%|$nginx_port|g" \
        "$TEMPLATES_DIR/nginx-proxy.conf.template" > "$nginx_conf"

    # 5. Ссылка на инструкцию
    ln -sf "$GUIDE_DIR/guide.md" "/home/$username/.user-services-guide.md"
    chown "$username:$username" "/home/$username/.user-services-guide.md"

    # Reload systemd
    systemctl daemon-reload

    # Enable and start services (от имени пользователя)
    sudo -u "$username" systemctl --user daemon-reload
    sudo -u "$username" systemctl --user enable --now code-server.socket nginx-proxy.service 2>/dev/null || true

    echo "Services setup completed for $username"
}

# Основной цикл
main() {
    # Создаём необходимые директории
    mkdir -p "$NGINX_CONF_DIR" "$TEMPLATES_DIR" "$GUIDE_DIR" "$SYSTEMD_USER_DIR"

    # Получаем список всех обычных пользователей
    getent passwd | while IFS=: read -r username _ uid _ _ home shell; do
        # Пропускаем системных пользователей и root
        [ "$uid" -lt 1000 ] && continue
        [ "$username" = "nobody" ] && continue
        [ ! -d "$home" ] && continue
        [[ "$shell" == *"nologin"* ]] && continue
        [[ "$shell" == *"false"* ]] && continue

        setup_user_services "$username" "$uid"
    done

    # Проверяем, что nginx включает наши конфиги
    if ! grep -q "include $NGINX_CONF_DIR/\*.conf;" /etc/nginx/nginx.conf 2>/dev/null; then
        echo "Adding include directive to nginx.conf..."
        sed -i '/http {/a\    include '"$NGINX_CONF_DIR"'/*.conf;' /etc/nginx/nginx.conf
        systemctl reload nginx
    fi

    echo "All user services have been updated"
}

main "$@"
