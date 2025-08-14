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

# Генерация пароля без специальных символов (только буквы и цифры)
PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 12)
IP=$(hostname -I | awk '{print $1}')

# Удаляем новый контейнер http-proxy, если он уже существует
docker rm -f http-proxy &>/dev/null

# Создаем временный файл конфигурации Squid
CONFIG_FILE=$(mktemp)
cat <<EOF > "$CONFIG_FILE"
http_port 3128
# Аутентификация (закомментирована для теста без аутентификации)
# auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
# auth_param basic realm Proxy Authentication
# acl authenticated proxy_auth REQUIRED
# http_access allow authenticated
http_access allow all
# Логирование для диагностики
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
# Разрешить все источники для теста
acl all src 0.0.0.0/0
EOF

# Создаем файл с учетными данными (на случай, если аутентификация нужна)
docker run --rm -v "$(pwd)":/mnt httpd:2.4 htpasswd -bc /mnt/passwd g0rox "$PASS"

# Запускаем контейнер с HTTP-прокси
docker run -d --name http-proxy \
  -p 3128:3128 \
  -v "$CONFIG_FILE:/etc/squid/squid.conf" \
  -v "$(pwd)/passwd:/etc/squid/passwd" \
  sameersbn/squid:latest

# Даем контейнеру больше времени на запуск
sleep 5

# Проверяем, запустился ли контейнер
if docker ps | grep -q http-proxy; then
  LINK="http://${IP}:3128"
  echo "[SUCCESS] HTTP-прокси запущен: $LINK"
  echo "[INFO] Для теста без аутентификации используйте указанный адрес."
  echo "[INFO] С аутентификацией: http://g0rox:${PASS}@${IP}:3128"
else
  echo "[ERROR] Не удалось запустить HTTP-прокси"
  echo "[INFO] Проверяю логи контейнера..."
  docker logs http-proxy
  exit 1
fi

# Проверка сетевой доступности порта
if nc -zv 127.0.0.1 3128 &>/dev/null; then
  echo "[INFO] Порт 3128 доступен локально"
else
  echo "[ERROR] Порт 3128 недоступен локально, проверьте брандмауэр или конфигурацию Docker"
fi

# Очищаем временный файл конфигурации
rm -f "$CONFIG_FILE"
rm -f "$(pwd)/passwd"