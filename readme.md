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
   - Глобальный nginx включает `/etc/nginx/user-services/*.conf`
   - Каждый пользователь получает свой `.conf` файл
   - Прокси на UNIX-сокет code-server
4. Инструкции через симлинки:
   ```bash
   ln -sf /usr/local/share/user-services/guide.md /home/$USER/.user-services-guide.md
   ```

### Структура артефактов:

```text
/etc/user-services/
├── config.ini                          # Основной конфиг
├── ports.db                            # БД портов: UID:nginx_port:codeserver_port
├── templates/
│   ├── nginx-proxy.conf.template       # Шаблон конфига nginx для include
│   ├── code-server.socket.template     # Шаблон сокета
│   ├── code-server.service.template    # Шаблон сервиса (активация через сокет)
│   └── nginx-proxy.service.template    # Шаблон сервиса nginx
└── scripts/
    ├── create-user-services.sh        # Основной скрипт настройки
    ├── allocate-ports.sh              # Аллокация портов
    ├── cleanup-user.sh                # Очистка пользователя
    ├── status-all.sh                  # Статус всех
    └── show-logs.sh                   # Логи пользователя

/usr/local/bin/
├── user-service-control               # Управление сервисами
├── user-service-recreate-configs      # Пересоздание конфигов
├── user-code-server-set-password      # Смена пароля
└── user-service-logs                  # Просмотр логов

/usr/local/share/user-services/
├── guide.md                           # Основная инструкция
├── ssh-setup.md                       # Настройка SSH
└── scripts/                           # Копии скриптов для справки

/etc/systemd/system/
├── user-services-setup.service        # Сервис настройки
└── user-services-setup.timer          # Таймер (каждые 12 часов)

/usr/lib/systemd/user/
└── lingering-enable.service           # Сервис для авто-включения лингеринга
```

### Глобальный конфиг `/etc/user-services/config.ini`
[config.ini](src/config.ini)

### Шаблон сокета `/etc/user-services/templates/code-server.socket.template`
[code-server.socket.template](src/templates/code-server.socket.template)

### Шаблон сервиса code-server `/etc/user-services/templates/code-server.service.template`
[code-server.service.template](src/templates/code-server.service.template)

### Шаблон конфига nginx `/etc/user-services/templates/nginx-proxy.conf.template`
[nginx-proxy.conf.template](src/templates/nginx-proxy.conf.template)

### Основной скрипт создания сервисов `/etc/user-services/scripts/create-user-services.sh`
[create-user-services.sh](src/scripts/create-user-services.sh)

### Таймер systemd `/etc/systemd/system/user-services-setup.timer`
[user-services-setup.timer](src/system_systemd/user-services-setup.timer)

### Сервис для таймера `/etc/systemd/system/user-services-setup.service`
[user-services-setup.service](src/system_systemd/user-services-setup.service)
