#!/bin/bash
# remove_customer.sh
# Bu script, belirli bir müşteriye ait WordPress ve DB container'larını (ve konfigürasyon dosyalarını)
# canlı sistemden kaldırır (soft delete). Veriler (Docker volume'lar) dokunulmadan kalır.
# Konfigürasyon dosyaları "archived_customers/<müşteri>/" altına taşınır.
#
# Uyarı: Bu işlem container'ları durdurur ve konfigürasyon dosyalarını arşivler, 
# volume'lar dokunmaz, böylece istersen daha sonra geri yükleyebilirsin.

set -e

# Müşteri adını interaktif alalım.
read -p "Silmek/Arşivlemek istediğiniz müşterinin adını girin (örn: musteri1): " CUSTOMER

# Docker Compose dosyası ve Nginx konfigürasyon dosyasının adlarını belirleyelim.
COMPOSE_FILE="docker-compose-${CUSTOMER}.yml"
NGINX_CONF_FILE="nginx_conf/${CUSTOMER}.conf"

# Müşteri konfigürasyon dosyalarının bulunduğu dizinlerin varlığını kontrol edelim.
if [ ! -f "${COMPOSE_FILE}" ]; then
    echo "Hata: ${COMPOSE_FILE} bulunamadı. Belirtilen müşteri sistemde yok gibi."
    exit 1
fi

if [ ! -f "${NGINX_CONF_FILE}" ]; then
    echo "Uyarı: ${NGINX_CONF_FILE} bulunamadı. Nginx konfigürasyonu yoksa devam edelim."
fi

echo "Müşteri '${CUSTOMER}' için soft deletion işlemi başlatılıyor..."

# 1. Docker Compose ile çalışan container'ları durdur ve kaldır (volume'lara dokunmadan).
echo "Containerlar durduruluyor..."
docker compose -f "${COMPOSE_FILE}" down
echo "Containerlar başarıyla durduruldu."

# 2. Konfigürasyon dosyalarını arşivleme:
ARCHIVE_DIR="./archived_customers/${CUSTOMER}"
mkdir -p "${ARCHIVE_DIR}"

echo "Docker Compose dosyası '${COMPOSE_FILE}' arşivleniyor..."
mv "${COMPOSE_FILE}" "${ARCHIVE_DIR}/"
echo "Nginx konfigürasyon dosyası '${NGINX_CONF_FILE}' arşivleniyor..."
if [ -f "${NGINX_CONF_FILE}" ]; then
    mv "${NGINX_CONF_FILE}" "${ARCHIVE_DIR}/"
fi

echo "Müşteri '${CUSTOMER}' için soft deletion işlemi tamamlandı."
echo "Containerlar durduruldu, konfigürasyon dosyaları '${ARCHIVE_DIR}' altına taşındı."
echo "Volume'lar korunuyor; gerekirse, müşteri verilerini geri yükleyebilirsin."
