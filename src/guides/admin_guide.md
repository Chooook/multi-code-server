
# Руководство администратора системы пользовательских сервисов

## 📋 Оглавление

1. [Обзор системы](#обзор-системы)
2. [Быстрый старт](#быстрый-старт)
3. [Архитектура](#архитектура)
4. [Установка и настройка](#установка-и-настройка)
5. [Управление пользователями](#управление-пользователями)
6. [Мониторинг и логи](#мониторинг-и-логи)
7. [Устранение неполадок](#устранение-неполадок)
8. [Безопасность](#безопасность)
9. [Расширенная настройка](#расширенная-настройка)
10. [FAQ](#faq)

## 🎯 Обзор системы

Система предоставляет каждому пользователю:
- **Code Server** (веб-версия VS Code) с автоматическим запуском/остановкой
- **Nginx прокси** для доступа через выделенный порт
- **Автоматическое управление** через systemd user units
- **Изоляцию** между пользователями

### Основные компоненты:

```
/etc/user-services/           # Конфигурация системы
├── config                   # Основной конфиг
├── ports.db                 # База портов пользователей
├── templates/               # Шаблоны конфигов
└── scripts/                 # Скрипты управления

/usr/local/bin/              # Пользовательские утилиты
├── user-service-control     # Управление сервисами
├── user-service-logs        # Просмотр логов
└── user-code-server-set-password # Смена пароля

/etc/systemd/user/           # Systemd юниты пользователей
/etc/nginx/user-services/    # Конфиги nginx
```

## 🚀 Быстрый старт

### Установка за 5 минут:

```bash
# 1. Скачайте и запустите установщик
git clone <repository>
cd user-services-system
sudo ./setup.sh

# 2. Проверьте установку
sudo /etc/user-services/scripts/status-all.sh

# 3. Проверьте одного пользователя
sudo /etc/user-services/scripts/show-logs.sh <username>
```

### Основные команды:

```bash
# Статус всех пользователей
sudo /etc/user-services/scripts/status-all.sh

# Очистка пользователя
sudo /etc/user-services/scripts/cleanup-user.sh <username>

# Просмотр логов
sudo /etc/user-services/scripts/show-logs.sh <username> [service]

# Ручной запуск настройки
sudo /etc/user-services/scripts/create-user-services.sh
```

## 🏗 Архитектура

### Поток работы:

```
Пользователь → Nginx (порт 10000+) → UNIX Socket → Code Server
      ↑                                          ↑
      |                                          |
  systemd (глобальный)                   systemd (пользовательский)
```

### Выделение портов:

```bash
# Алгоритм:
# 1. Базовый порт = BASE_PORT + (UID % 10000)
# 2. Если занят → порт + 1
# 3. Записывается в /etc/user-services/ports.db

# Пример:
UID 1001 → nginx порт: 11001, codeserver порт: 21001
```

### Systemd сервисы:

- **code-server.socket** - Слушает UNIX socket, запускает сервис при подключении
- **code-server.service** - Сам code-server, останавливается через 1 час без активности
- **nginx-proxy.service** - Локальный nginx для проксирования

## 🔧 Установка и настройка

### Требования:

- Linux с systemd
- Nginx
- Code-server (установится автоматически или вручную)
- Bash 4.0+

### Полная установка:

```bash
# 1. Клонируйте репозиторий
git clone <repository-url>
cd user-services-system

# 2. Запустите установщик
chmod +x setup.sh
sudo ./setup.sh

# 3. Или для быстрой установки без code-server
sudo ./setup.sh --quick
```

### Проверка установки:

```bash
# Тест всех компонентов
sudo ./setup.sh --test

# Проверка статуса
sudo /etc/user-services/scripts/status-all.sh

# Проверка nginx
curl http://localhost:9999  # тестовый эндпоинт
```

### Настройка конфигурации:

Основной конфиг: `/etc/user-services/config`

```ini
# Диапазоны портов
NGINX_PROXY_PORT_MIN=10000
NGINX_PROXY_PORT_MAX=19999
NGINX_BASE_PORT=10000
CODESERVER_BASE_PORT=20000

# Таймаут бездействия (секунды)
CODESERVER_IDLE_TIMEOUT=3600

# Директории
SYSTEMD_USER_DIR=/etc/systemd/user
NGINX_CONF_DIR=/etc/nginx/user-services
```

## 👥 Управление пользователями

### Автоматическая настройка:

Система автоматически настраивает сервисы для всех пользователей с:
- UID ≥ 1000
- Домашней директорией
- Рабочей оболочкой (не /bin/false, /usr/sbin/nologin)

Частота проверки: **каждые 12 часов**

### Ручное управление:

```bash
# Принудительная настройка всех пользователей
sudo /etc/user-services/scripts/create-user-services.sh

# Настройка конкретного пользователя
sudo /etc/user-services/scripts/create-user-services.sh --user <username>

# Очистка пользователя
sudo /etc/user-services/scripts/cleanup-user.sh <username>
sudo /etc/user-services/scripts/cleanup-user.sh 1001  # по UID

# Проверка портов
cat /etc/user-services/ports.db
```

### Добавление нового пользователя:

```bash
# 1. Создайте пользователя
adduser newuser

# 2. Автоматически (через 12 часов максимум)
# Или вручную:
sudo /etc/user-services/scripts/create-user-services.sh --user newuser

# 3. Дайте пользователю начальный пароль
sudo cat /home/newuser/.code-server-initial-password.txt
```

### Удаление пользователя:

```bash
# 1. Очистите сервисы
sudo /etc/user-services/scripts/cleanup-user.sh <username>

# 2. Удалите пользователя
deluser --remove-home <username>
```

## 📊 Мониторинг и логи

### Общий статус:

```bash
# Полный отчет
sudo /etc/user-services/scripts/status-all.sh

# Только активные пользователи
sudo /etc/user-services/scripts/status-all.sh | grep -E "(✓|ACTIVE)"

# Проверка портов
ss -tuln | grep -E ":(1[0-9]{4}|2[0-9]{4})"
```

### Просмотр логов:

```bash
# Все логи пользователя
sudo /etc/user-services/scripts/show-logs.sh <username>

# Логи code-server
sudo /etc/user-services/scripts/show-logs.sh <username> code-server

# Логи nginx
sudo /etc/user-services/scripts/show-logs.sh <username> nginx

# Поиск ошибок
sudo /etc/user-services/scripts/show-logs.sh <username> search "error"
```

### Systemd логи:

```bash
# Логи глобального systemd
journalctl -u user-services-setup.service
journalctl -u user-services-setup.timer

# Логи пользовательских сервисов
sudo -u <username> journalctl --user -u code-server.service
```

### Nginx логи:

```bash
# Доступ к логам
tail -f /var/log/nginx/user-<username>-access.log
tail -f /var/log/nginx/user-<username>-error.log

# Мониторинг активности
tail -f /var/log/nginx/access.log | grep :<порт>
```

## 🔍 Устранение неполадок

### Общие проблемы:

#### 1. Code-server не устанавливается
```bash
# Установите вручную
curl -fsSL https://code-server.dev/install.sh | sh
# или
sudo snap install code-server --classic
```

#### 2. Nginx не запускается
```bash
# Проверьте конфигурацию
nginx -t

# Проверьте включение user-services
grep "include.*user-services" /etc/nginx/nginx.conf

# Перезапустите
systemctl restart nginx
```

#### 3. Пользовательские сервисы не работают
```bash
# Проверьте linger
loginctl show-user <username> | grep Linger

# Включите linger
loginctl enable-linger <username>

# Проверьте user systemd
sudo -u <username> systemctl --user daemon-reload
```

#### 4. Порт недоступен
```bash
# Проверьте занятость порта
ss -tuln | grep :<порт>

# Проверьте настройки firewall
iptables -L -n | grep <порт>
ufw status | grep <порт>

# Перевыделите порты
rm /etc/user-services/ports.db
sudo /etc/user-services/scripts/create-user-services.sh
```

### Диагностика:

```bash
# Полная диагностика пользователя
sudo /etc/user-services/scripts/status-all.sh | grep <username>
sudo /etc/user-services/scripts/show-logs.sh <username> all
sudo -u <username> systemctl --user status

# Проверка сокетов
sudo -u <username> ss -xp | grep code-server

# Проверка процессов
ps aux | grep <username> | grep -E "(code-server|nginx)"
```

## 🔒 Безопасность

### Рекомендации:

1. **Обновляйте регулярно:**
   ```bash
   # Code-server
   sudo snap refresh code-server
   # или
   sudo /usr/local/bin/code-server --update
   
   # Nginx
   sudo apt update && sudo apt upgrade nginx
   ```

2. **Настройте firewall:**
   ```bash
   # Разрешите только необходимые порты
   sudo ufw allow 22/tcp
   sudo ufw allow from <trusted_network> to any port 10000:19999
   sudo ufw enable
   ```

3. **Мониторинг активности:**
   ```bash
   # Подозрительная активность
   grep -E "(failed|error|attack)" /var/log/nginx/*.log
   
   # Много запросов с одного IP
   awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -nr
   ```

4. **Ротация логов:**
   ```bash
   # Добавьте в /etc/logrotate.d/nginx-user-services
   /var/log/nginx/user-*.log {
       daily
       missingok
       rotate 14
       compress
       delaycompress
       notifempty
       create 0640 www-data adm
       sharedscripts
       postrotate
           systemctl reload nginx
       endscript
   }
   ```

### Изоляция пользователей:

- Каждый пользователь имеет свои systemd юниты
- Сервисы запускаются от имени пользователя
- Нет доступа между пользователями
- UNIX сокеты с правами 0660

## ⚙ Расширенная настройка

### Изменение диапазонов портов:

```bash
# Отредактируйте конфиг
sudo nano /etc/user-services/config

# Измените:
NGINX_PROXY_PORT_MIN=15000
NGINX_PROXY_PORT_MAX=15999

# Пересоздайте конфиги
rm /etc/user-services/ports.db
sudo /etc/user-services/scripts/create-user-services.sh
```

### Изменение таймаута бездействия:

```bash
# В конфиге
CODESERVER_IDLE_TIMEOUT=1800  # 30 минут

# В шаблоне templates/code-server.socket.tpl
IdleTimeoutSec=1800

# Примените изменения
sudo /etc/user-services/scripts/create-user-services.sh
```

### Добавление новых сервисов:

1. Создайте шаблоны в `/etc/user-services/templates/`
2. Добавьте логику в `create-user-services.sh`
3. Протестируйте на одном пользователе

### Резервное копирование:

```bash
# Конфигурация системы
sudo tar -czf user-services-backup-$(date +%Y%m%d).tar.gz \
  /etc/user-services \
  /etc/nginx/user-services \
  /etc/systemd/user/*.service \
  /etc/systemd/user/*.socket

# Пользовательские данные (опционально)
for user in /home/*; do
    if [ -d "$user/.config/code-server" ]; then
        sudo tar -czf "$user-code-server-$(date +%Y%m%d).tar.gz" \
          "$user/.config/code-server" \
          "$user/.local/share/code-server"
    fi
done
```

## ❓ FAQ

### Q: Как изменить пароль пользователю?
A: Пользователь может сменить пароль сам: `user-code-server-set-password`
   Или администратор может сбросить:
   ```bash
   sudo rm /home/<user>/.config/code-server/config.yaml
   sudo /etc/user-services/scripts/create-user-services.sh --user <user>
   ```

### Q: Как увеличить количество пользователей?
A: Измените диапазоны портов в конфиге. Максимум 10к пользователей на диапазон.

### Q: Сервис не останавливается через час
A: Проверьте:
   ```bash
   # Активны ли соединения
   sudo -u <user> ss -xp | grep code-server
   
   # Проверьте настройки сокета
   sudo -u <user> systemctl --user show code-server.socket | grep IdleTimeout
   ```

### Q: Как отключить автоматическую настройку?
A: 
   ```bash
   systemctl disable --now user-services-setup.timer
   ```

### Q: Пользователь жалуется на "Connection refused"
A: Проверьте цепочку:
   1. `sudo /etc/user-services/scripts/status-all.sh | grep <user>`
   2. `curl -I http://localhost:<порт>`
   3. `sudo /etc/user-services/scripts/show-logs.sh <user> nginx`

### Q: Как мигрировать на другой сервер?
A:
   1. Скопируйте `/etc/user-services/`
   2. Скопируйте `/etc/nginx/user-services/`
   3. Скопируйте `/etc/systemd/user/*.service`
   4. Запустите `create-user-services.sh`

## 📞 Поддержка

### Логи для отладки:

При обращении за помощью предоставьте:
```bash
# Системная информация
sudo /etc/user-services/scripts/status-all.sh

# Логи проблемного пользователя
sudo /etc/user-services/scripts/show-logs.sh <username> all 100

# Конфигурация
grep -v "^#" /etc/user-services/config
```

### Полезные команды:

```bash
# Перезапуск всей системы
sudo systemctl restart nginx
sudo /etc/user-services/scripts/create-user-services.sh

# Сброс одного пользователя
sudo /etc/user-services/scripts/cleanup-user.sh <username>
sudo /etc/user-services/scripts/create-user-services.sh --user <username>
```

---
*Версия системы: 0.1.0*
*Обновлено: $(date +%Y-%m-%d)*
*Для обновлений проверяйте репозиторий проекта*
