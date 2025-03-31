#!/bin/bash
# 🐾 MEOW BACKUP TO GOOGLE DRIVE - V2

set -euo pipefail

# === KULLANICI BİLGİLERİNİ AL ===
echo "🔐 SQL Server SA şifresi (örnek: M30w1903Database):"
read -rsp "> " SQL_PASSWORD && echo
echo "☁️  Google Drive için rclone remote adınızı girin (örnek: GoogleDrive):"
read -rp "> " REMOTE_NAME
echo "📂 Google Drive'da yedeklerin depolanacağı klasör adını girin (örnek: Meow_Backups):"
read -rp "> " REMOTE_DIR

BACKUP_DIR="$HOME/meow-backup"
LOG_DIR="$BACKUP_DIR/logs"
STACK_DIR="$HOME/meow-stack"
TIMESTAMP=$(date +%F-%H%M)

# SQL Server yedeklerinin bulunduğu dizinler:
HOST_SQL_BACKUP_DIR="$BACKUP_DIR/sql"
CONTAINER_SQL_BACKUP_DIR="/var/opt/mssql/backup"

# SQL komutlarını çalıştırmak için fonksiyon tanımı
sql_exec() {
    /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SQL_PASSWORD" -Q "$1"
}

mkdir -p "$BACKUP_DIR" "$LOG_DIR" "$HOST_SQL_BACKUP_DIR"

# === LOG DOSYASINI HAZIRLA ===
LOG_FILE="$LOG_DIR/backup-$TIMESTAMP.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "📦 Yedekleme işlemi başlıyor... [$TIMESTAMP]"

# === NGINX STACK ARŞİVİ ===
echo "🗄️  Nginx stack arşivleniyor..."
if [ -d "$STACK_DIR" ]; then
    sudo tar -czf "$BACKUP_DIR/nginx-stack-$TIMESTAMP.tar.gz" "$STACK_DIR" || echo "⚠️  Arşivlenirken bazı dosyalar atlandı."
else
    echo "❌ $STACK_DIR klasörü bulunamadı!"
fi

# === SQL Yedekleme ===
echo "🧠 SQL Server veritabanları yedekleniyor..."

DATABASES=$(/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SQL_PASSWORD" -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4;" -h -1 | tr -d '\r')

for db in $DATABASES; do
    # Host üzerinde oluşturulacak yedek dosyasının adını belirle
    BAKFILE="$HOST_SQL_BACKUP_DIR/${db}-${TIMESTAMP}.bak"
    echo "📀 $db yedekleniyor..."
    # SQL Server container içindeki mount noktası üzerinden yedekleme yapacak:
    sql_exec "BACKUP DATABASE [$db] TO DISK = N'$CONTAINER_SQL_BACKUP_DIR/$(basename "$BAKFILE")' WITH INIT"
done

# === rclone Kontrolü ===
if ! command -v rclone &>/dev/null; then
    echo "⚠️ rclone bulunamadı. Lütfen setup aşamasını kontrol edin!"
    exit 1
fi

# === GOOGLE DRIVE'A YÜKLE ===
echo "☁️ Google Drive'a yükleniyor..."
rclone copy "$BACKUP_DIR" "$REMOTE_NAME:$REMOTE_DIR" --log-file "$LOG_DIR/upload-$TIMESTAMP.log" --quiet || echo "⚠️ Yükleme sırasında hata oluştu!"

# === LOKAL TEMİZLİK (7 GÜN) ===
echo "🧹 7 günden eski yedekler temizleniyor..."
find "$BACKUP_DIR" -type f -mtime +7 -exec rm -f {} \;

# === TAMAMLANDI ===
echo "✅ Yedekleme tamamlandı!"
echo "📁 Yedek klasörü: $BACKUP_DIR"
echo "📄 Log dosyası: $LOG_FILE"
echo "☁️ Remote: $REMOTE_NAME:$REMOTE_DIR"
