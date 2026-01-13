#!/bin/bash
# Скрипт создания/обновления сервисов для пользователей
# Запускается из systemd timer раз в 12 часов

CONFIG_FILE="/etc/user-services/config"
source "$CONFIG_FILE"

# Функция создания сервисов для пользователя
setup_user_services() {
    local username="$1"
    local uid="$2"

    echo "Setting up services for user: $username (UID: $uid)"

    # Включаем лингеринг
    loginctl enable-linger "$username"

    # Аллокация портов
    local ports
    ports=$("$SCRIPTS_DIR/allocate-ports.sh" "$uid" "$username")
    local nginx_port=$(echo "$ports" | cut -d: -f1)
    local codeserver_port=$(echo "$ports" | cut -d: -f2)

    # Создаём хеш пароля по умолчанию (первый запуск)
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

        # Сохраняем пароль для пользователя (только на первую настройку)
        echo "Initial code-server password for $username: $password" > "/home/$username/.code-server-initial-password.txt"
        chown "$username:$username" "/home/$username/.code-server-initial-password.txt"
        chmod 600 "/home/$username/.code-server-initial-password.txt"
    fi

    # Создаём конфиг code-server если его нет
    mkdir -p "$config_dir"
    cat > "$config_file" << EOF
bind-addr: unix:/run/user/$uid/code-server.sock
auth: password
password: $password_hash
cert: false
user-data-dir: /home/$username/.local/share/code-server
extensions-dir: /home/$username/.local/share/code-server/extensions
EOF
    chown -R "$username:$username" "$config_dir"

    # Шаблонизация конфигов systemd
    for template in code-server.socket code-server.service nginx-proxy.service; do
        local dest="$SYSTEMD_USER_DIR/${template//%i/$username}"

        # Заменяем переменные в шаблоне
        sed \
            -e "s|%i|$username|g" \
            -e "s|%UID%|$uid|g" \
            -e "s|%PASSWORD_HASH%|$password_hash|g" \
            -e "s|%CODESERVER_PORT%|$codeserver_port|g" \
            -e "s|%NGINX_PORT%|$nginx_port|g" \
            "$TEMPLATES_DIR/$template.tpl" > "$dest"

        chmod 644 "$dest"
        echo "Created: $dest"
    done

    # Конфиг nginx
    local nginx_conf="$NGINX_CONF_DIR/$username.conf"
    sed \
        -e "s|%i|$username|g" \
        -e "s|%UID%|$uid|g" \
        -e "s|%NGINX_PORT%|$nginx_port|g" \
        "$TEMPLATES_DIR/nginx-proxy.conf.tpl" > "$nginx_conf"

    # Ссылка на инструкцию
    ln -sf "$GUIDE_DIR/guide.md" "/home/$username/.user-services-guide.md"
    chown "$username:$username" "/home/$username/.user-services-guide.md"

    # Reload systemd и nginx
    systemctl daemon-reload
    systemctl reload nginx

    # Enable and start services
    sudo -u "$username" systemctl --user daemon-reload
    sudo -u "$username" systemctl --user enable --now code-server.socket nginx-proxy.service

    echo "Services setup completed for $username"
}

# Основной цикл
main() {
    # Создаём необходимые директории
    mkdir -p "$NGINX_CONF_DIR" "$TEMPLATES_DIR" "$GUIDE_DIR"

    # Получаем список всех обычных пользователей (UID >= 1000, кроме nobody)
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
    if ! grep -q "include $NGINX_CONF_DIR/\*.conf;" /etc/nginx/nginx.conf; then
        echo "Adding include directive to nginx.conf..."
        sed -i '/http {/a\    include '"$NGINX_CONF_DIR"'/*.conf;' /etc/nginx/nginx.conf
    fi

    echo "All user services have been updated"
}

main "$@"
