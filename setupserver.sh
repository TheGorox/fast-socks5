#!/bin/bash
if ! command -v docker &>/dev/null; then
  echo "[INFO] Docker не найден, устанавливаю..."
  apt update && apt install -y docker.io
  systemctl enable --now docker
fi

PASS=$(openssl rand -base64 12)
IP=$(hostname -I | awk '{print $1}')

docker rm -f socks5 &>/dev/null

docker run -d --name socks5 -p 1099:1080 \
  -e PROXY_USER=g0rox \
  -e PROXY_PASSWORD="$PASS" \
  serjs/go-socks5-proxy

LINK="socks5://g0rox:${PASS}@${IP}:1099"
echo "[SUCCESS] Прокси запущен: $LINK"
