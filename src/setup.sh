#!/bin/bash
# Полная установка системы пользовательских сервисов
# Требует запуска от root

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Пути

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETC_DIR="/etc/auto-code-server"
BIN_DIR="/usr/local/bin"
GUIDE_DIR="/usr/local/share/auto-code-server"
EXCLUDED_USERS_DIR="/etc/auto-code-server/excluded_users"

# Функция вывода с цветом
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Проверка прав root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Этот скрипт должен быть запущен от root"
        return 1
    fi
}

# Проверка зависимостей
check_dependencies() {
    print_status "Проверка зависимостей..."

    local missing_deps=()

    # Проверяем systemd
    if ! command -v systemctl >/dev/null 2>&1; then
        missing_deps+=("systemd")
    fi

    # Проверяем code-server
    if ! command -v code-server >/dev/null 2>&1; then
        print_warning "code-server не установлен. Установите его вручную или используйте официальный скрипт."
        read -p "Продолжить установку? (code-server можно установить позже) [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi

    # Проверяем необходимые утилиты
    for cmd in ss getent loginctl sed grep awk cut sort uniq openssl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Отсутствуют зависимости: ${missing_deps[*]}"

        # Предлагаем установить
        if command -v apt-get >/dev/null 2>&1; then
            print_status "Попытка установки через apt-get..."
            apt-get update
            apt-get install -y "${missing_deps[@]}"
        elif command -v yum >/dev/null 2>&1; then
            print_status "Попытка установки через yum..."
            yum install -y "${missing_deps[@]}"
        elif command -v dnf >/dev/null 2>&1; then
            print_status "Попытка установки через dnf..."
            dnf install -y "${missing_deps[@]}"
        else
            print_error "Установите зависимости вручную и перезапустите скрипт"
            return 1
        fi
    fi

    print_success "Все зависимости удовлетворены"
}

# Установка code-server (опционально)
install_code_server() {
    if command -v code-server >/dev/null 2>&1; then
        print_success "code-server уже установлен"
        return
    fi

    print_status "Установка code-server..."

    # Скачиваем и устанавливаем fallback версию
    wget https://github.com/coder/code-server/releases/download/v4.107.1/code-server-4.107.1-linux-amd64.tar.gz
    tar -xzvf code-server-4.107.1-linux-amd64.tar.gz

    sudo cp -r code-server-4.107.1-linux-amd64 /usr/lib/code-server
    sudo ln -s /usr/lib/code-server/bin/code-server /usr/bin/code-server
    sudo mkdir /var/lib/code-server

    print_success "code-server установлен"
}

# Создание структуры директорий
create_directories() {
    print_status "Создание структуры директорий..."

    mkdir -p "$ETC_DIR"/{scripts,templates}
    mkdir -p "$BIN_DIR"
    mkdir -p "$GUIDE_DIR"
    mkdir -p "$EXCLUDED_USERS_DIR"

    # Устанавливаем правильные права
    chmod 755 "$ETC_DIR"
    chmod 1777 "EXCLUDED_USERS_DIR"

    print_success "Директории созданы"
}

# Копирование файлов конфигурации
copy_config_files() {
    print_status "Копирование файлов конфигурации..."

    # Шаблоны
    cp "$SCRIPT_DIR/templates"/*.template "$ETC_DIR/templates/"
    chmod 644 "$ETC_DIR/templates"/*.template

    # Systemd юниты
    cp "$SCRIPT_DIR/system_systemd"/*.service "/etc/systemd/system"
    cp "$SCRIPT_DIR/system_systemd"/*.timer "/etc/systemd/system"

    # Руководства
    cp "$SCRIPT_DIR/guides"/*.md "$GUIDE_DIR/"
    chmod 644 "$GUIDE_DIR"/*.md

    # Исполняемые скрипты
    for script in allocate-port code-server-control user-service-logs cleanup-my-code-server disable-auto-code-server-creation; do
        cp "$SCRIPT_DIR/user_scripts/$script" "$BIN_DIR/"
        chmod 755 "$BIN_DIR/$script"
    done

    # Root скрипты
    for script in create-code-servers.sh status-all.sh show-logs.sh; do
        cp "$SCRIPT_DIR/scripts/$script" "$ETC_DIR/scripts/"
        chmod 755 "$ETC_DIR/scripts/$script"
    done

    print_success "Файлы конфигурации скопированы"
}

# Настройка systemd таймера
configure_systemd() {
    print_status "Настройка systemd..."

    # Перезагружаем демон systemd
    systemctl daemon-reload

    # Включаем и запускаем таймер
    if systemctl enable code-servers-setup.timer 2>/dev/null; then
        print_success "Таймер code-servers-setup.timer включен"
    else
        print_error "Не удалось включить таймер"
    fi

    if systemctl start code-servers-setup.timer 2>/dev/null; then
        print_success "Таймер code-servers-setup.timer запущен"
    else
        print_error "Не удалось запустить таймер"
    fi

    # Проверяем статус
    print_status "Проверка статуса таймера..."
    systemctl status code-servers-setup.timer --no-pager --lines=3
}

# Запуск первоначальной настройки пользователей
run_initial_setup() {
    print_status "Запуск создания сервисов для существующих пользователей..."


    if [ -x "$ETC_DIR/scripts/create-code-servers.sh" ]; then
        "$ETC_DIR/scripts/create-code-servers.sh"

        if [ $? -eq 0 ]; then
            print_success "Создание сервисов завершено успешно"
        else
            print_warning "Создание сервисов завершено с ошибками"
        fi
    else
        print_error "Скрипт создания сервисов не найден: $ETC_DIR/scripts/create-code-servers.sh"
    fi
}

# Тестирование установки
test_installation() {
    print_status "Тестирование установки..."

    local tests_passed=0
    local tests_failed=0

    # Тест 1: Проверка существования директорий
    for dir in "$ETC_DIR" "$BIN_DIR" "$GUIDE_DIR" "$EXCLUDED_USERS_DIR"; do
        if [ -e "$dir" ]; then
            print_success "Директория/файл существует: $dir"
            tests_passed=$((tests_passed + 1))
        else
            print_error "Директория/файл отсутствует: $dir"
            tests_failed=$((tests_failed + 1))
        fi
    done

    # Тест 2: Проверка исполняемых скриптов
    for script in code-server-control allocate-port cleanup-my-code-server disable-auto-code-server-creation user-service-logs; do
        if [ -x "$BIN_DIR/$script" ]; then
            print_success "Скрипт исполняем: $script"
            tests_passed=$((tests_passed + 1))
        else
            print_error "Скрипт не исполняем: $script"
            tests_failed=$((tests_failed + 1))
        fi
    done

    # Тест 3: Проверка systemd таймера
    if systemctl is-enabled code-servers-setup.timer >/dev/null 2>&1; then
        print_success "Systemd таймер включен"
        tests_passed=$((tests_passed + 1))
    else
        print_error "Systemd таймер не включен"
        tests_failed=$((tests_failed + 1))
    fi

    echo ""
    print_status "Результаты тестирования:"
    echo "  Пройдено: $tests_passed"
    echo "  Провалено: $tests_failed"

    if [ $tests_failed -eq 0 ]; then
        print_success "Все тесты пройдены успешно!"
        return 0
    else
        print_warning "Некоторые тесты провалены. Проверьте установку."
        return 1
    fi
}

# Показ итоговой информации
show_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                 УСТАНОВКА ЗАВЕРШЕНА                     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "📁 Директории:"
    echo "  Конфиги:          $ETC_DIR"
    echo "  Шаблоны:          $ETC_DIR/templates/"
    echo "  Руководства:      $GUIDE_DIR"
    echo ""
    echo "🛠 Утилиты:"
    echo "  code-server-control            # Управление сервисом"
    echo "  user-service-logs              # Просмотр логов"
    echo "  allocate-port                  # Подбор свободного порта"
    echo "  cleanup-my-code-server         # Очистка сервисов"
    echo "  disable-auto-code-server-creation  # Отключение автоматического создания сервисов"
    echo ""
    echo "⚙ Systemd:"
    echo "  Таймер:          code-servers-setup.timer"
    echo "  Сервис:          code-servers-setup.service"
    echo "  Частота:         Каждые 12 часов"
    echo ""
    echo "🔧 Проверка установки:"
    echo "  sudo $ETC_DIR/scripts/status-all.sh"
    echo ""
    echo "📖 Документация:"
    echo "  Руководство администратора: $GUIDE_DIR/admin-auto-code-server-guide.md"
    echo "  Руководство пользователя:   $GUIDE_DIR/user-auto-code-server-guide.md"
    echo ""
    echo "🚀 Следующие шаги:"
    echo "  1. Проверьте статус: sudo $ETC_DIR/scripts/status-all.sh"
    echo "  2. Настройте пользователей вручную если нужно"
    echo "  3. Протестируйте на одном пользователе"
    echo ""
    echo -e "${YELLOW}Примечание: code-server должен быть установлен для работы системы${NC}"
    if ! command -v code-server >/dev/null 2>&1; then
        echo "  Установите: curl -fsSL https://code-server.dev/install.sh | sh"
    fi
}

# Основная функция
main() {
    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        Установка all-users code-server       ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    check_root
    check_dependencies

    # Предлагаем установить code-server
    read -p "Установить code-server автоматически? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_code_server
    fi

    create_directories
    copy_config_files
    configure_systemd
    run_initial_setup
    test_installation
    show_summary

    print_success "Установка завершена!"
}

# Обработка аргументов командной строки
case "${1:-}" in
    --help|-h)
        echo "Использование: $0 [опции]"
        echo ""
        echo "Опции:"
        echo "  --help, -h     Показать эту справку"
        echo "  --test         Только тестирование зависимостей"
        echo "  --quick        Быстрая установка без code-server"
        echo ""
        echo "Примеры:"
        echo "  $0              Полная установка"
        echo "  $0 --test       Проверка зависимостей"
        echo "  $0 --quick      Установка без code-server"
        return 0
        ;;
    --test)
        check_root
        check_dependencies
        return 0
        ;;
    --quick)
        check_root
        check_dependencies
        create_directories
        copy_config_files
        configure_systemd
        test_installation
        show_summary
        return 0
        ;;
    *)
        main
        ;;
esac
