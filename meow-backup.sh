#!/bin/bash
# 🐾 MEOW BACKUP TO GOOGLE DRIVE - V2

set -e

# === KULLANICI BİLGİLERİNİ AL ===
echo "🔐 SQL Server SA şifresi (örnek: M30w1903Database):"
read -rsp "> " SQL_PASSWORD && echo

REMOTE_NAME="GoogleDrive"
REMOTE_DIR="Meow_Backups"
BACKUP_DIR="$HOME/meow-backup"
LOG_DIR="$BACKUP_DIR/logs"
STACK_DIR="$HOME/nginx-stack"
TIMESTAMP=$(date +%F-%H%M)
SQLCMD="sqlcmd -S localhost -U sa -P \"$SQL_PASSWORD\""
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

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
mkdir -p "$BACKUP_DIR/sql"

DATABASES=$(eval $SQLCMD -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4;" -h -1 | tr -d '\r')

for db in $DATABASES; do
    BAKFILE="$BACKUP_DIR/sql/$db-$TIMESTAMP.bak"
    echo "📀 $db yedekleniyor..."
    eval $SQLCMD -Q "BACKUP DATABASE [$db] TO DISK = N'$BAKFILE' WITH INIT"
done

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

