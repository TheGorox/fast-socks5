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

PASS=$(openssl rand -base64 12)
IP=$(hostname -I | awk '{print $1}')

# Удаляем новый контейнер http-proxy, если он уже существует
docker rm -f http-proxy &>/dev/null

# Создаем временный файл конфигурации Squid
CONFIG_FILE=$(mktemp)
cat <<EOF > "$CONFIG_FILE"
http_port 3128
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm Proxy Authentication
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
EOF

# Создаем файл с учетными данными
docker run --rm -v "$(pwd)":/mnt busybox sh -c "echo 'g0rox:$(echo -n '$PASS' | openssl dgst -md5 -binary | openssl enc -base64)' > /mnt/passwd"

# Запускаем контейнер с HTTP-прокси
docker run -d --name http-proxy \
  -p 3128:3128 \
  -v "$CONFIG_FILE:/etc/squid/squid.conf" \
  -v "$(pwd)/passwd:/etc/squid/passwd" \
  sameersbn/squid:latest

# Даем контейнеру время на запуск
sleep 2

# Проверяем, запустился ли контейнер
if docker ps | grep -q http-proxy; then
  LINK="http://g0rox:${PASS}@${IP}:3128"
  echo "[SUCCESS] HTTP-прокси запущен: $LINK"
else
  echo "[ERROR] Не удалось запустить HTTP-прокси"
  exit 1
fi

# Очищаем временный файл конфигурации
rm -f "$CONFIG_FILE"
rm -f "$(pwd)/passwd"