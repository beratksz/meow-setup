#!/bin/bash
# 🐾 MEOW BACKUP TO GOOGLE DRIVE SCRIPT (Tam Otomatik Kurulum)

set -e

### 🧾 KULLANICIDAN GEREKLİ BİLGİLERİ AL ###
echo "🔐 SQL Server şifresini girin (örnek: M30w1903Database):"
read -rsp "> " SQL_PASSWORD
echo

echo "☁️ Google Drive için rclone remote adı girin (örnek: GoogleDrive):"
read -rp "> " REMOTE_NAME

echo "📂 Google Drive klasör adı girin (örnek: Meow_Backups):"
read -rp "> " REMOTE_DIR

### 📦 RCLONE KURULUMU & KONFİG ###
echo "📦 rclone kuruluyor..."
if ! command -v rclone &> /dev/null; then
  curl https://rclone.org/install.sh | sudo bash
fi

if [ ! -f "$HOME/.config/rclone/rclone.conf" ]; then
  echo "⚙️  rclone yapılandırması başlatılıyor..."
  rclone config
else
  echo "✅ rclone zaten yapılandırılmış."
fi

### 📁 DİZİN AYARLARI ###
BACKUP_DIR="$HOME/backup"
LOG_DIR="$BACKUP_DIR/logs"
TIMESTAMP=$(date +%F-%H%M)
SQL_CONTAINER_NAME="sqlserver"
SQL_BACKUP_DIR="/var/opt/mssql/backups"

mkdir -p "$BACKUP_DIR" "$LOG_DIR"

### 📦 NGINX + DOCKER STACK YEDEKLE ###
echo "📦 Nginx stack yedekleniyor..."
tar -czf "$BACKUP_DIR/nginx-stack-$TIMESTAMP.tar.gz" "$HOME/meow-stack"

### 🐳 Docker container'ları ve image'ları yedekle ###
echo "🐳 Docker image ve container ayarları yedekleniyor..."
docker image save -o "$BACKUP_DIR/docker-images-$TIMESTAMP.tar" $(docker images --format '{{.Repository}}:{{.Tag}}')
docker ps -a --format '{{.Names}}' | while read container; do
  docker inspect "$container" > "$BACKUP_DIR/${container}_inspect_$TIMESTAMP.json"
done

### 🧠 SQL SERVER - TÜM DB'LERİ YEDEKLE ###
echo "🧠 SQL Server'daki tüm veritabanları yedekleniyor..."
docker exec "$SQL_CONTAINER_NAME" /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P "$SQL_PASSWORD" \
  -Q "EXEC sp_MSforeachdb 'IF DB_ID(''?') > 4 BEGIN BACKUP DATABASE [?] TO DISK = ''$SQL_BACKUP_DIR/?.bak'' END'"

# .bak dosyalarını host'a çek
for bakfile in $(docker exec "$SQL_CONTAINER_NAME" sh -c "ls $SQL_BACKUP_DIR | grep .bak"); do
  docker cp "$SQL_CONTAINER_NAME:$SQL_BACKUP_DIR/$bakfile" "$BACKUP_DIR/$bakfile-$TIMESTAMP"
done

### ☁️ GOOGLE DRIVE'A GÖNDER ###
echo "☁️ Google Drive'a yükleniyor..."
rclone copy "$BACKUP_DIR" "$REMOTE_NAME:$REMOTE_DIR" --log-file "$LOG_DIR/upload-$TIMESTAMP.log"

### 🧹 ESKİ YEDEKLERİ SİL (7 GÜN) ###
echo "🧹 7 günden eski yedekler siliniyor..."
find "$BACKUP_DIR" -type f -mtime +7 -exec rm -f {} \;

### ⏰ CRON JOB EKLE (günde 1 kere 03:00'te) ###
if ! crontab -l | grep -q "meow-backup.sh"; then
  (crontab -l 2>/dev/null; echo "0 3 * * * bash $HOME/meow-setup/meow-backup.sh >> $LOG_DIR/cron-$(date +\%F).log 2>&1") | crontab -
  echo "🕒 Cron job eklendi: Her gün saat 03:00'te yedek alınacak."
else
  echo "ℹ️ Cron job zaten mevcut."
fi

### ✅ TAMAMLANDI ###
echo ""
echo "✅ Yedekleme tamamlandı: $TIMESTAMP"
echo "📂 Yedek dizini: $BACKUP_DIR"
echo "📄 Log dosyası: $LOG_DIR/upload-$TIMESTAMP.log"
echo "☁️ Google Drive hedefi: $REMOTE_NAME:$REMOTE_DIR"

