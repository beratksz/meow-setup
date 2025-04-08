#!/bin/bash
# setup_all.sh
# Bu script:
#   1) Docker network 'wp_network' kontrol eder, yoksa oluşturur.
#   2) Müşteri bilgilerini alır: müşteri adı, port son eki, domain.
#   3) Müşteri için WP & DB container'larını tanımlayan docker-compose dosyasını oluşturur ve ayağa kaldırır.
#   4) ./nginx_conf dizininde müşteriye özel Nginx konfigürasyon dosyası oluşturur.
#   5) Nginx reverse proxy container'ını (aynı network içinde) başlatır veya konfigürasyonu güncelleyip reload eder.
# Not: Reverse proxy docker compose dosyasında Nginx, ./nginx_conf dizinini /etc/nginx/conf.d olarak mount eder.
#
# Eğer volume mount konusunda sorun yaşarsan, ./nginx_conf dizininin absolute path'ini kullanabilirsin.

set -e

########################################
# 1. Docker Network Kontrolü
########################################
NETWORK_NAME="wp_network"
if ! docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}\$"; then
  echo "Docker network '${NETWORK_NAME}' bulunamadı. Oluşturuluyor..."
  docker network create ${NETWORK_NAME}
else
  echo "Docker network '${NETWORK_NAME}' zaten mevcut."
fi

########################################
# 2. Müşteri Bilgilerini Al
########################################
read -p "Müşteri adını girin (örn: musteri1): " CUSTOMER
read -p "Port son ekini girin (örn: 01, 02, vs.): " PORT_SUFFIX
read -p "Domain ismini girin (örn: musteri1.ornekdomain.com): " DOMAIN

# Varsayılan veritabanı bilgileri
WP_DB_NAME="wp_db_${CUSTOMER}"
WP_DB_USER="wp_user_${CUSTOMER}"
WP_DB_PASS="wp_pass_${CUSTOMER}"
ROOT_PASS="root_pass_${CUSTOMER}"

########################################
# 3. Docker Compose Dosyasını Oluştur (WP & DB)
########################################
# Dosya adında boşluk olmamasına dikkat edelim.
COMPOSE_FILE="docker-compose-${CUSTOMER}.yml"

cat > "${COMPOSE_FILE}" <<EOF
version: '3.8'
services:
  wordpress_${CUSTOMER}:
    image: wordpress:latest
    container_name: wordpress_${CUSTOMER}
    restart: always
    ports:
      - "80${PORT_SUFFIX}:80"   # Örnek: 8001, 8002 gibi.
    environment:
      WORDPRESS_DB_HOST: db_${CUSTOMER}:3306
      WORDPRESS_DB_USER: ${WP_DB_USER}
      WORDPRESS_DB_PASSWORD: ${WP_DB_PASS}
      WORDPRESS_DB_NAME: ${WP_DB_NAME}
    volumes:
      - wordpress_data_${CUSTOMER}:/var/www/html
    networks:
      - ${NETWORK_NAME}
    depends_on:
      - db_${CUSTOMER}

  db_${CUSTOMER}:
    image: mysql:5.7
    container_name: db_${CUSTOMER}
    restart: always
    environment:
      MYSQL_DATABASE: ${WP_DB_NAME}
      MYSQL_USER: ${WP_DB_USER}
      MYSQL_PASSWORD: ${WP_DB_PASS}
      MYSQL_ROOT_PASSWORD: ${ROOT_PASS}
    volumes:
      - db_data_${CUSTOMER}:/var/lib/mysql
    networks:
      - ${NETWORK_NAME}

volumes:
  wordpress_data_${CUSTOMER}:
  db_data_${CUSTOMER}:

networks:
  ${NETWORK_NAME}:
    external: true
EOF

echo "Docker Compose dosyası '${COMPOSE_FILE}' oluşturuldu."
echo "WordPress ve DB container'ları başlatılıyor..."
docker compose -f "${COMPOSE_FILE}" up -d

########################################
# 4. Nginx Konfigürasyon Dosyası Oluştur
########################################
# Nginx konfigürasyon dosyalarını barındıracağımız dizin
NGINX_CONF_DIR="./nginx_conf"
mkdir -p "${NGINX_CONF_DIR}"

NGINX_CONF_FILE="${NGINX_CONF_DIR}/${CUSTOMER}.conf"

cat > "${NGINX_CONF_FILE}" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://wordpress_${CUSTOMER}:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

echo "Nginx konfigürasyon dosyası oluşturuldu: ${NGINX_CONF_FILE}"

########################################
# 5. Nginx Reverse Proxy Container'ı
########################################
# Reverse proxy için docker-compose dosyasının olduğu dizin
NGINX_COMPOSE_DIR="nginx_proxy"
NGINX_COMPOSE_FILE="${NGINX_COMPOSE_DIR}/docker-compose.yml"

# Eğer reverse proxy dizini yoksa oluştur ve dosyayı yaz.
if [ ! -d "${NGINX_COMPOSE_DIR}" ]; then
  mkdir -p "${NGINX_COMPOSE_DIR}"
  cat > "${NGINX_COMPOSE_FILE}" <<'EOF'
version: "3.8"
services:
  reverse-proxy:
    image: nginx:latest
    container_name: reverse-proxy
    restart: always
    ports:
      - "80:80"
    volumes:
      - ./nginx_conf:/etc/nginx/conf.d:ro
    networks:
      - wp_network

networks:
  wp_network:
    external: true
EOF
  echo "Nginx reverse proxy docker-compose dosyası oluşturuldu: ${NGINX_COMPOSE_FILE}"
fi

# Reverse proxy container'ının çalışıp çalışmadığını kontrol edelim.
if ! docker ps --format '{{.Names}}' | grep -q "^reverse-proxy\$"; then
  echo "Nginx reverse proxy container'ı çalışmıyor, başlatılıyor..."
  (cd "${NGINX_COMPOSE_DIR}" && docker compose up -d)
else
  echo "Nginx reverse proxy container'ı zaten çalışıyor, konfigürasyon güncellendi, yeniden yüklüyor..."
  docker exec reverse-proxy nginx -s reload
fi

echo ""
echo "Tüm işlemler tamamlandı."
echo "Müşteri '${CUSTOMER}' için WordPress ve DB container'ları çalışıyor."
echo "Domain '${DOMAIN}' reverse proxy sayesinde yönlendirilecektir."
echo "Cloudflare A kaydının sunucunun public IP'sine ayarlandığından emin ol."
