#!/bin/bash
# 🐾 MEOW BACKUP TO GOOGLE DRIVE SCRIPT (Tam Otomatik)

set -e

# === Bilgi Toplama ===
echo "🔐 SQL Server şifresini girin (örnek: M30w1903Database):"
read -rsp "> " SQL_PASSWORD
echo

echo "☁️  Google Drive için rclone remote adı girin (örnek: GoogleDrive):"
read -rp "> " REMOTE_NAME

echo "📂 Google Drive klasör adı (örnek: Meow_Backups):"
read -rp "> " REMOTE_DIR

# === rclone Kontrolü ===
echo "📦 rclone kurulumu kontrol ediliyor..."
if ! command -v rclone &> /dev/null; then
    curl https://rclone.org/install.sh | sudo bash
fi

if [ ! -f "$HOME/.config/rclone/rclone.conf" ]; then
    echo "⚙️  rclone yapılandırması başlatılıyor..."
    rclone config
else
    echo "✅ rclone zaten yapılandırılmış."
fi

# === Dizinler ===
BACKUP_DIR="$HOME/meow-backup"
LOG_DIR="$BACKUP_DIR/logs"
TIMESTAMP=$(date +%F-%H%M)
SQL_CONTAINER_NAME="sqlserver"
SQL_BACKUP_DIR="/var/opt/mssql/backups"

mkdir -p "$BACKUP_DIR" "$LOG_DIR"

# === Nginx Stack Yedekleme ===
echo "📦 Nginx stack arşivleniyor..."
tar -czf "$BACKUP_DIR/nginx-stack-$TIMESTAMP.tar.gz" "$HOME/nginx-stack" 2>/dev/null || echo "⚠️ Bazı dosyalar okunamadı (izin hatası olabilir)."

# === SQL Yedekleme ===
echo "🧠 SQL Server veritabanları yedekleniyor..."
if docker exec "$SQL_CONTAINER_NAME" test -f /opt/mssql-tools/bin/sqlcmd; then
    docker exec "$SQL_CONTAINER_NAME" mkdir -p "$SQL_BACKUP_DIR"
    docker exec "$SQL_CONTAINER_NAME" /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U sa -P "$SQL_PASSWORD" \
        -Q "EXEC sp_MSforeachdb 'IF DB_ID(''?') > 4 BEGIN BACKUP DATABASE [?] TO DISK = ''$SQL_BACKUP_DIR/?.bak'' END'"
else
    echo "⚠️ SQL yedeği alınırken hata oluştu! sqlcmd aracı yok veya yol hatalı."
fi

# === .bak dosyalarını host'a çek ===
echo "📁 Yedeklenen .bak dosyaları dışa aktarılıyor..."
for bakfile in $(docker exec "$SQL_CONTAINER_NAME" sh -c "ls $SQL_BACKUP_DIR 2>/dev/null | grep .bak" || true); do
    docker cp "$SQL_CONTAINER_NAME:$SQL_BACKUP_DIR/$bakfile" "$BACKUP_DIR/$bakfile-$TIMESTAMP" || true
done

# === Google Drive'a Gönder ===
echo "☁️ Google Drive'a yükleniyor..."
rclone copy "$BACKUP_DIR" "$REMOTE_NAME:$REMOTE_DIR" --log-file "$LOG_DIR/upload-$TIMESTAMP.log" || echo "⚠️ Google Drive'a gönderim başarısız!"

# === Eski Yedekleri Sil (7 gün) ===
echo "🧹 Eski yedekler temizleniyor (7 günden eski)..."
find "$BACKUP_DIR" -type f -mtime +7 -exec rm -f {} \;

# === Tamam ===
echo "✅ Tüm yedekleme işlemleri başarıyla tamamlandı!"
echo "📂 Lokalde: $BACKUP_DIR"
echo "📄 Log: $LOG_DIR/upload-$TIMESTAMP.log"
echo "☁️ Remote: $REMOTE_NAME:$REMOTE_DIR"

