# FIXME!!!!!!!!!!!!!
Ключевые особенности реализации

1. Сокетная активация code-server:
   - `code-server.socket` слушает UNIX-сокет с `IdleTimeoutSec=3600`
   - Nginx проксирует на `unix:/run/user/$UID/code-server.sock`
   - При первом запросе → запуск code-server
   - Час без запросов → остановка
2. Автоматический лингеринг:
   - При создании конфигов добавляем пользователя в лингеринг 
   - `loginctl enable-linger $USERNAME`
3. Проксирование через nginx:
   - Глобальный nginx включает `/etc/nginx/auto-code-server/*.conf`
   - Каждый пользователь получает свой `.conf` файл
   - Прокси на UNIX-сокет code-server
4. Инструкции через симлинки:
   ```bash
   ln -sf /usr/local/share/auto-code-server/user-auto-code-server-guide.md /home/$USER/.user-auto-code-server-guide.md
   ```

### Структура артефактов:

```text
/etc/auto-code-server/                        # ETC_DIR
├── config                                 # Основной конфиг
├── templates/
│   ├── nginx-proxy.conf.template          # Шаблон конфига nginx для include
│   ├── code-server.socket.template        # Шаблон сокета
│   ├── code-server.service.template       # Шаблон сервиса (активация через сокет)
│   └── nginx-proxy.service.template       # Шаблон сервиса nginx
│   ├── code-server.env.template            # Шаблон для EnvironmentFile
└── scripts/                               # TEMPLATES_DIR
    ├── create-auto-code-server.sh            # Основной скрипт настройки
    ├── allocate-port.sh                  # Аллокация порта
    ├── cleanup-user.sh                    # Очистка пользователя
    ├── status-all.sh                      # Статус всех
    └── show-logs.sh                       # Логи пользователя

/usr/local/bin/                            # BIN_DIR
├── user-service-control                   # Управление сервисами
├── user-service-recreate-configs          # Пересоздание конфигов
├── user-code-server-set-password          # Смена пароля
└── user-service-logs                      # Просмотр логов

/usr/local/share/auto-code-server/            # GUIDE_DIR
├── user-auto-code-server-guide.md                               # Основная инструкция
└── scripts/                               # Копии скриптов для справки

/etc/systemd/system/                       # SYSTEMD_SYSTEM_DIR
├── auto-code-server-setup.service            # Сервис настройки
└── auto-code-server-setup.timer              # Таймер (каждые 12 часов)

/usr/lib/systemd/user/ (или /etc/systemd/user ?)  # SYSTEMD_USER_DIR
└── lingering-enable.service               # Сервис для авто-включения лингеринга

/home/<user>/.config/code-server/
├── config.yaml                            # Основной конфиг code-server
└── environment                            # Файл переменных окружения (генерируется)

/etc/nginx/auto-code-server                   # NGINX_CONF_DIR
└── ???

/var/log/nginx/auto-code-server
└── logs?
```
