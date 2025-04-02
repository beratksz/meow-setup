#!/bin/bash

# CapRover Otomatik Kurulum Scripti v2
# Kullanım: bash meow-caprover-v2.sh <IP_ADRESI> <DOMAIN>

set -e

IP="$1"
DOMAIN="$2"

if [[ -z "$IP" || -z "$DOMAIN" ]]; then
  echo "\n❌ Kullanım: bash meow-caprover-v2.sh <IP_ADRESI> <DOMAIN>"
  echo "   Örnek: bash meow-caprover-v2.sh 46.197.32.51 caprover.beratoksz.com"
  exit 1
fi

clear
echo "🐳 CapRover Otomatik Kurulum Başlıyor..."
sleep 1

# 1. Docker temizle
echo "🔧 Docker kaldırılıyor (varsa)..."
sudo systemctl stop docker.socket || true
sudo systemctl stop docker || true
sudo docker swarm leave --force || true
sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
sudo rm -rf /var/lib/docker /etc/docker /var/run/docker.sock /captain || true

# 2. Docker kurulumu
echo "🔄 Docker kuruluyor..."
curl -fsSL https://get.docker.com | sh
sudo systemctl enable docker
sudo systemctl start docker

# 3. Docker Compose kurulumu
sudo apt install -y docker-compose

# 4. CapRover Docker Compose dosyası
mkdir -p ~/caprover && cd ~/caprover

cat > docker-compose.yml <<EOF
version: '3'
services:
  caprover:
    container_name: caprover
    image: caprover/caprover
    restart: always
    ports:
      - 80:80
      - 443:443
      - 3000:3000
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /captain:/captain
    environment:
      - MAIN_NODE_IP_ADDRESS=$IP
      - CAPROVER_ROOT_DOMAIN=$DOMAIN
      - ACCEPTED_TERMS=true
EOF

# 5. CapRover başlat
echo "🚀 CapRover container başlatılıyor..."
docker-compose up -d

# 6. DNS kontrol
echo "🔍 DNS kontrol ediliyor..."
resolve_ip=$(dig +short $DOMAIN | tail -n1)
if [[ "$resolve_ip" == "$IP" ]]; then
  echo "✅ DNS doğrulandı: $DOMAIN → $IP"
else
  echo "⚠️  Uyarı: DNS henüz IP'ye eşlemedi: $DOMAIN ≠ $IP"
  echo "⏳ Devam edebilmek için DNS kaydını kontrol et!"
fi

# 7. Bilgilendirme
echo "\n🎉 Kurulum tamam! Tarayıcıdan aç:"
echo "➡ http://$DOMAIN:3000/#/setup"
echo "\n🧠 Not: Kurulumdan sonra swarm hatası alırsan:"
echo "   docker swarm leave --force"
echo "   docker rm -f caprover"
echo "   sudo rm -rf /captain"
echo "   docker-compose up -d"
echo "\n✔ Hazır olduğunda tarayıcıdan setup ekranı gelir."
