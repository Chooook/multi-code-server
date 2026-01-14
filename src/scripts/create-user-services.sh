#!/bin/bash
# Скрипт создания/обновления сервисов для пользователей

MAIN_CONFIG="/etc/user-services/config"
[ -f "$MAIN_CONFIG" ] && source "$MAIN_CONFIG" || {
    echo "Config file not found: $MAIN_CONFIG"
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

    # Создаём конфигурационные файлы из шаблонов

    # 1. Systemd service files
    for template in code-server.socket code-server.service nginx-proxy.service; do
        local dest="$SYSTEMD_USER_DIR/$template.$username"

        sed \
            -e "s|%i|$username|g" \
            -e "s|%UID%|$uid|g" \
            -e "s|%PASSWORD_HASH%|$password_hash|g" \
            -e "s|%CODESERVER_PORT%|$codeserver_port|g" \
            -e "s|%NGINX_PORT%|$nginx_port|g" \
            "$TEMPLATES_DIR/$template.template" > "$dest"

        chmod 644 "$dest"
    done

    # 2. Code-server config
    local config_dir="/home/$username/.config/code-server"
    local codeserver_config="$config_dir/config.yaml"

    # Генерируем случайный пароль и хеш
    local password=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-12)
    local password_hash=$(echo -n "$password" | sha256sum | cut -d' ' -f1)

    # Сохраняем пароль для пользователя
    local password_file="/home/$username/.code-server-password.txt"
    echo "Initial code-server password for $username: $password" > $password_file
    chown "$username:$username" "/home/$username/.code-server-initial-password.txt"
    chmod 600 "/home/$username/.code-server-initial-password.txt"

    cat > "$codeserver_config" << EOF
bind-addr: unix:/run/user/$uid/code-server.sock
auth: password
password: $password_hash
cert: false
user-data-dir: /home/$username/.local/share/code-server
extensions-dir: /home/$username/.local/share/code-server/extensions
EOF
    chown "$username:$username" "$codeserver_config"
    chmod 600 "$codeserver_config"

    # 3. Environment file
    local env_file="/home/$username/.config/code-server/environment"
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
