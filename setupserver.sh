#!/bin/bash
if ! command -v docker &>/dev/null; then
  echo "[INFO] Docker не найден, устанавливаю..."
  apt update && apt install -y docker.io
  systemctl enable --now docker
fi

# Остановка и удаление старого SOCKS5 контейнера, если он существует
if docker ps -a | grep -q socks5; then
  echo "[INFO] Обнаружен старый SOCKS5 контейнер, останавливаю и удаляю..."
  docker stop socks5 &>/dev/null
  docker rm socks5 &>/dev/null
fi

# Остановка и удаление старого Squid контейнера, если он существует
if docker ps -a | grep -q http-proxy; then
  echo "[INFO] Обнаружен старый Squid контейнер, останавливаю и удаляю..."
  docker stop http-proxy &>/dev/null
  docker rm http-proxy &>/dev/null
fi

# Генерация пароля без специальных символов (на случай включения аутентификации)
PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 12)
IP=$(hostname -I | awk '{print $1}')

# Удаляем новый контейнер tinyproxy, если он уже существует
docker rm -f tinyproxy &>/dev/null

# Создаем временный файл конфигурации Tinyproxy
CONFIG_FILE=$(mktemp)
cat <<EOF > "$CONFIG_FILE"
Port 2846
Listen 0.0.0.0
Timeout 600
LogLevel Info
MaxClients 100
# Аутентификация отключена для теста
BasicAuth g0rox $PASS
Allow 0.0.0.0/0
EOF

# Запускаем контейнер с Tinyproxy
docker run -d --name tinyproxy \
  -p 2846:2846 \
  -v "$CONFIG_FILE:/etc/tinyproxy/tinyproxy.conf" \
  vimagick/tinyproxy:latest

# Даем контейнеру время на запуск
sleep 5

# Проверяем, запустился ли контейнер
if docker ps | grep -q tinyproxy; then
  LINK="http://g0rox:${PASS}@${IP}:2846"
  echo "[SUCCESS] HTTP-прокси (Tinyproxy) запущен: $LINK"
  echo "[INFO] Для теста используйте указанный адрес без аутентификации."
  echo "[INFO] Пароль (для включения аутентификации): g0rox:$PASS"
else
  echo "[ERROR] Не удалось запустить HTTP-прокси (Tinyproxy)"
  echo "[INFO] Проверяю логи контейнера..."
  docker logs tinyproxy
  exit 1
fi

# Проверка сетевой доступности порта
if nc -zv 127.0.0.1 2846 &>/dev/null; then
  echo "[INFO] Порт 2846 доступен локально"
else
  echo "[ERROR] Порт 2846 недоступен локально, проверьте брандмауэр или конфигурацию Docker"
fi

# Очищаем временный файл конфигурации
rm -f "$CONFIG_FILE"