#!/bin/bash
# backup_all.sh
# Bu script; mevcut dizinde bulunan docker-compose-*.yml dosyalarından müşteri adlarını tespit eder,
# her müşteri için WordPress ve DB volume'larını yedekleyip, yedekleri ayrı klasörlere kaydeder.
#
# Not: Bu script, Alpine container'ı kullanarak Docker volume içeriklerini tar ile arşivler.
#       Volume'ların adı, setup_all.sh'de oluşturduğun isimlendirme standartlarına bağlı olarak
#       "wordpress_data_<müşteri>" ve "db_data_<müşteri>" şeklinde olmalı.

set -e

# Yedeklerin konulacağı ana klasör
BACKUP_ROOT="./backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

mkdir -p "$BACKUP_ROOT"

# Mevcut dizinde docker-compose-*.yml dosyalarını döngüye al
for file in docker-compose-*.yml; do
    # Örneğin: "docker-compose-kohesoft.yml" -> "kohesoft" 
    CUSTOMER=$(basename "$file")
    CUSTOMER=${CUSTOMER#docker-compose-}
    CUSTOMER=${CUSTOMER%.yml}

    echo "Müşteri: $CUSTOMER için yedekleme yapılıyor..."

    # Her müşteri için yedek klasörü oluştur
    CUSTOMER_BACKUP_DIR="$BACKUP_ROOT/$CUSTOMER"
    mkdir -p "$CUSTOMER_BACKUP_DIR"

    # WordPress volume yedeği (örn: wordpress_data_kohesoft)
    WP_VOLUME="wordpress_data_${CUSTOMER}"
    WP_BACKUP_FILE="${WP_VOLUME}_${TIMESTAMP}.tar.gz"
    echo "  WordPress volume yedekleniyor: $WP_VOLUME"
    docker run --rm \
       -v "${WP_VOLUME}":/volume \
       -v "$CUSTOMER_BACKUP_DIR":/backup \
       alpine sh -c "cd /volume && tar czf /backup/$(basename "$WP_BACKUP_FILE") ."

    # DB volume yedeği (örn: db_data_kohesoft)
    DB_VOLUME="db_data_${CUSTOMER}"
    DB_BACKUP_FILE="${DB_VOLUME}_${TIMESTAMP}.tar.gz"
    echo "  DB volume yedekleniyor: $DB_VOLUME"
    docker run --rm \
       -v "${DB_VOLUME}":/volume \
       -v "$CUSTOMER_BACKUP_DIR":/backup \
       alpine sh -c "cd /volume && tar czf /backup/$(basename "$DB_BACKUP_FILE") ."

    echo "  $CUSTOMER için yedekleme tamamlandı. Yedekler: $CUSTOMER_BACKUP_DIR"
done

echo "Tüm yedekleme işlemleri tamamlandı."
