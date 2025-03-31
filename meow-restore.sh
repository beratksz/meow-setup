#!/bin/bash
# 🐾 MEOW RESTORE FROM BACKUP SCRIPT (Tam Otomatik)

set -euo pipefail

echo "🧠 SQL Server SA şifresini girin (örnek: M30w1903Database):"
read -rsp "> " SQL_PASSWORD && echo

BACKUP_DIR="$HOME/meow-backup"
STACK_ARCHIVE=$(ls -t "$BACKUP_DIR"/nginx-stack-*.tar.gz | head -n 1)
SQL_DIR="$BACKUP_DIR/sql"

# === LOG DOSYASI ===
TIMESTAMP=$(date +%F-%H%M%S)
LOG_FILE="$BACKUP_DIR/logs/restore-$TIMESTAMP.log"
mkdir -p "$BACKUP_DIR/logs"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "📦 Geri yükleme işlemi başlıyor... [$TIMESTAMP]"

# === meow-stack'i geri çıkar ===
echo "📁 Arşiv çıkarılıyor: $STACK_ARCHIVE"
if [ -f "$STACK_ARCHIVE" ]; then
    sudo tar -xzf "$STACK_ARCHIVE" -C "$HOME"
    echo "✅ meow-stack klasörü geri yüklendi."
else
    echo "❌ Arşiv dosyası bulunamadı!"
    exit 1
fi

# === SQL yedeklerini geri yükle ===
echo "🧠 SQL veritabanları geri yükleniyor..."
if [ -d "$SQL_DIR" ]; then
    for bak in "$SQL_DIR"/*.bak; do
        # DB adını dosya adının ilk kısmından alıyoruz (ilk '-' karakterine kadar)
        DBNAME=$(basename "$bak" | cut -d'-' -f1)
        # Container içerisindeki yedek dosyası yolu:
        FILE_IN_CONTAINER="/var/opt/mssql/backup/$(basename "$bak")"
        echo "🔁 $DBNAME geri yükleniyor..."
        sqlcmd -S localhost -U sa -P "$SQL_PASSWORD" -Q "RESTORE DATABASE [$DBNAME] FROM DISK = N'$FILE_IN_CONTAINER' WITH REPLACE"
    done
    echo "✅ Tüm veritabanları geri yüklendi."
else
    echo "❌ SQL yedek dizini bulunamadı: $SQL_DIR"
    exit 1
fi

# === Docker Compose ile stack'i yeniden başlat ===
echo "🐳 Docker container'ları yeniden başlatılıyor..."
cd "$HOME/meow-stack"
# Eğer docker-compose yüklüyse bu komut, Docker Compose Plugin kullanıyorsanız "docker compose up -d" olabilir.
docker-compose up -d

# === Tamamlandı ===
echo "✅ Geri yükleme işlemi tamamlandı."
echo "📂 Stack dizini: $HOME/meow-stack"
echo "🗃️ Yedek klasörü: $BACKUP_DIR"
echo "📄 Log dosyası: $LOG_FILE"
