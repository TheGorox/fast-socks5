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

# Остановка и удаление старого Tinyproxy контейнера, если он существует
if docker ps -a | grep -q tinyproxy; then
  echo "[INFO] Обнаружен старый Tinyproxy контейнер, останавливаю и удаляю..."
  docker stop tinyproxy &>/dev/null
  docker rm tinyproxy &>/dev/null
fi

# Генерация пароля без специальных символов
PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 12)
IP=$(hostname -I | awk '{print $1}')
PORT=2846

# Создаем временный файл конфигурации Tinyproxy
CONFIG_FILE=$(mktemp)
cat <<EOF > "$CONFIG_FILE"
Port $PORT
Listen 0.0.0.0
Timeout 600
LogLevel Info
MaxClients 100
BasicAuth g0rox $PASS
Allow 0.0.0.0/0
EOF

# Открываем порт в iptables
echo "[INFO] Открываю порт $PORT в iptables..."
iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
iptables -I DOCKER-USER -i eth0 -p tcp --dport $PORT -j ACCEPT

# Запускаем контейнер с Tinyproxy
docker run -d --name tinyproxy \
  -p $PORT:$PORT \
  -v "$CONFIG_FILE:/etc/tinyproxy/tinyproxy.conf" \
  vimagick/tinyproxy:latest

# Даем контейнеру время на запуск
sleep 5

# Проверяем, запустился ли контейнер
if docker ps | grep -q tinyproxy; then
  LINK="http://g0rox:${PASS}@${IP}:${PORT}"
  echo "[SUCCESS] HTTP-прокси (Tinyproxy) запущен: $LINK"
else
  echo "[ERROR] Не удалось запустить HTTP-прокси (Tinyproxy)"
  echo "[INFO] Проверяю логи контейнера..."
  docker logs tinyproxy
  exit 1
fi

# Проверка локальной доступности порта
if nc -zv 127.0.0.1 $PORT &>/dev/null; then
  echo "[INFO] Порт $PORT доступен локально"
else
  echo "[ERROR] Порт $PORT недоступен локально, проверьте брандмауэр или конфигурацию Docker"
fi

# Проверка внешней доступности порта
if nc -zv ${IP} $PORT &>/dev/null; then
  echo "[INFO] Порт $PORT доступен на внешнем IP"
else
  echo "[ERROR] Порт $PORT недоступен на внешнем IP, проверьте брандмауэр или настройки сети"
fi

# Очищаем временный файл конфигурации
rm -f "$CONFIG_FILE"