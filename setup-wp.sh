#!/bin/bash
# setup_customer_wp.sh - Müşteri için izole WordPress ve DB ortamını kurar.

set -e

# Gerekli bilgileri kullanıcıdan sırayla alalım.
read -p "Müşteri adını girin (örneğin: musteri1): " CUSTOMER
read -p "Port son ekini girin (örn: 01, 02, vs.): " PORT_SUFFIX
read -p "Domain ismini girin (örn: musteri1.ornekdomain.com): " DOMAIN

# Varsayılan değerler tanımlanıyor.
WP_DB_NAME="wp_db_${CUSTOMER}"
WP_DB_USER="wp_user_${CUSTOMER}"
WP_DB_PASS="wp_pass_${CUSTOMER}"
ROOT_PASS="root_pass_${CUSTOMER}"

# Docker Compose dosyasının ismini dinamik olarak belirleyelim:
COMPOSE_FILE="docker-compose-${CUSTOMER}.yml"

cat > ${COMPOSE_FILE} <<EOF
version: '3.8'
services:
  wordpress_${CUSTOMER}:
    image: wordpress:latest
    container_name: wordpress_${CUSTOMER}
    restart: always
    ports:
      - "80${PORT_SUFFIX}:80"  # Örneğin, 8001, 8002 gibi.
    environment:
      WORDPRESS_DB_HOST: db_${CUSTOMER}:3306
      WORDPRESS_DB_USER: ${WP_DB_USER}
      WORDPRESS_DB_PASSWORD: ${WP_DB_PASS}
      WORDPRESS_DB_NAME: ${WP_DB_NAME}
    volumes:
      - wordpress_data_${CUSTOMER}:/var/www/html
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

volumes:
  wordpress_data_${CUSTOMER}:
  db_data_${CUSTOMER}:
EOF

echo "Docker Compose dosyası '${COMPOSE_FILE}' oluşturuldu."

# Containerları başlatıyoruz.
docker-compose -f ${COMPOSE_FILE} up -d

if [ \$? -eq 0 ]; then
  echo "Containerlar başarıyla başlatıldı."
  echo "Artık tarayıcınızdan 'http://${DOMAIN}' veya sunucunuzun public IP'si ve ilgili porta erişerek WordPress kurulumunu tamamlayabilirsiniz."
else
  echo "Containerlar başlatılırken bir hata oluştu."
fi

echo "Kurulum tamamlandı. WordPress admin ayarlarını ilk erişimde kurulum sihirbazından yapabilirsiniz."
