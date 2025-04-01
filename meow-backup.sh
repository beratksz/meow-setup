#!/bin/bash
# 🐾 MEOW BACKUP TO GOOGLE DRIVE - V2

set -euo pipefail

# Config dosyasını kontrol et ve yükle
CONFIG_FILE="$HOME/meow-setup/config.env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Config dosyası bulunamadı! Lütfen $CONFIG_FILE dosyasını oluşturun."
    exit 1
fi

# Config dosyasındaki bilgiler
echo "SQL Server SA şifresi: ********"
echo "rclone remote adı: $REMOTE_NAME"
echo "Google Drive yedek klasörü: $REMOTE_DIR"

# Varsayılan dizinler
BACKUP_DIR="$HOME/meow-backup"
LOG_DIR="$BACKUP_DIR/logs"
STACK_DIR="$HOME/meow-stack"
TIMESTAMP=$(date +%F-%H%M)

# SQL Server yedeklerinin tutulacağı dizinler:
HOST_SQL_BACKUP_DIR="$BACKUP_DIR/sql"
CONTAINER_SQL_BACKUP_DIR="/var/opt/mssql/backup"

# SQL komutlarını çalıştırmak için fonksiyon
sql_exec() {
    /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SQL_PASSWORD" -Q "$1"
}

# Gerekli dizinleri oluştur
mkdir -p "$BACKUP_DIR" "$LOG_DIR" "$HOST_SQL_BACKUP_DIR"

# Host tarafındaki SQL backup dizininin izinlerini ayarla (container genelde UID 10001 ile çalışır)
sudo chown -R $(whoami):$(whoami) "$HOST_SQL_BACKUP_DIR"
sudo chmod -R 755 "$HOST_SQL_BACKUP_DIR"


# LOG dosyasını oluştur
LOG_FILE="$LOG_DIR/backup-$TIMESTAMP.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "📦 Yedekleme işlemi başlıyor... [$TIMESTAMP]"

# === NGINX STACK ARŞİVİ Yedekleme ===
echo "🗄️  Nginx stack arşivleniyor..."
if [ -d "$STACK_DIR" ]; then
    sudo tar -czf "$BACKUP_DIR/nginx-stack-$TIMESTAMP.tar.gz" "$STACK_DIR" || echo "⚠️ Arşivlenirken bazı dosyalar atlandı."
else
    echo "❌ $STACK_DIR klasörü bulunamadı!"
fi

# === SQL Yedekleme ===
echo "🧠 SQL Server veritabanları yedekleniyor..."

# Container'da backup dizininin varlığını kontrol et (container 'sqlserver' çalışıyorsa)
if docker ps --format '{{.Names}}' | grep -q '^sqlserver$'; then
    docker exec sqlserver mkdir -p "$CONTAINER_SQL_BACKUP_DIR" || true
else
    echo "⚠️ 'sqlserver' container'ı çalışmıyor. SQL yedeği alınamıyor!"
    exit 1
fi

# SQL veritabanı isimlerini al (sistem veritabanları hariç)
DATABASES=$(/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SQL_PASSWORD" -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4;" -h -1 | tr -d '\r')
if [ -z "$DATABASES" ]; then
    echo "⚠️ Hiçbir kullanıcı veritabanı bulunamadı!"
    exit 1
fi

for db in $DATABASES; do
    # Host üzerinde oluşturulacak yedek dosyasının adını belirle
    BAKFILE="$HOST_SQL_BACKUP_DIR/${db}-${TIMESTAMP}.bak"
    echo "📀 $db yedekleniyor..."
    # SQL Server, container içindeki mount noktası üzerinden yedekleme yapacak:
    sql_exec "BACKUP DATABASE [$db] TO DISK = N'$CONTAINER_SQL_BACKUP_DIR/$(basename "$BAKFILE")' WITH INIT"
done

# === rclone Kontrolü ve Yükleme ===
if ! command -v rclone &>/dev/null; then
    echo "⚠️ rclone bulunamadı. Lütfen setup aşamasını kontrol edin!"
    exit 1
fi

echo "☁️ Google Drive'a yükleniyor..."
rclone copy "$BACKUP_DIR" "$REMOTE_NAME:$REMOTE_DIR" --log-file "$LOG_DIR/upload-$TIMESTAMP.log" --quiet || echo "⚠️ Yükleme sırasında hata oluştu!"

# === Eski Yedeklerin Temizlenmesi (7 Gün) ===
echo "🧹 7 günden eski yedekler temizleniyor..."
sudo find "$BACKUP_DIR" -type f -mtime +7 -exec rm -f {} \;

# === TAMAMLANDI ===
echo "✅ Yedekleme tamamlandı!"
echo "📁 Yedek klasörü: $BACKUP_DIR"
echo "📄 Log dosyası: $LOG_FILE"
echo "☁️ Remote: $REMOTE_NAME:$REMOTE_DIR"
