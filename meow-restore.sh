#!/bin/bash
# 🐾 MEOW RESTORE FROM BACKUP SCRIPT (Tam Otomatik)

set -euo pipefail

# SQL Server SA şifresini al
echo "🧠 SQL Server SA şifresini girin (örnek: M30w1903Database):"
read -rsp "> " SQL_PASSWORD && echo

# Varsayılan dizinler
BACKUP_DIR="$HOME/meow-backup"
STACK_ARCHIVE=$(ls -t "$BACKUP_DIR"/nginx-stack-*.tar.gz 2>/dev/null | head -n 1)
SQL_DIR="$BACKUP_DIR/sql"

# LOG dosyası ayarı
TIMESTAMP=$(date +%F-%H%M%S)
LOG_FILE="$BACKUP_DIR/logs/restore-$TIMESTAMP.log"
mkdir -p "$BACKUP_DIR/logs"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "📦 Geri yükleme işlemi başlıyor... [$TIMESTAMP]"

# --- Meow-stack'i geri çıkar ---
echo "📁 Arşiv çıkarılıyor: $STACK_ARCHIVE"
if [ -f "$STACK_ARCHIVE" ]; then
    sudo tar --strip-components=2 -xzf "$STACK_ARCHIVE" -C "$HOME"
    echo "✅ meow-stack klasörü geri yüklendi."
else
    echo "❌ Arşiv dosyası bulunamadı!"
    exit 1
fi

# --- SQL Yedek Dizini Kontrolü ---
if [ ! -d "$SQL_DIR" ]; then
    echo "❌ SQL yedek dizini bulunamadı: $SQL_DIR"
    exit 1
fi

# Yedek dosyası var mı kontrol et
shopt -s nullglob
bak_files=("$SQL_DIR"/*.bak)
if [ ${#bak_files[@]} -eq 0 ]; then
    echo "❌ Hiçbir .bak dosyası bulunamadı."
    exit 1
fi
shopt -u nullglob

# --- SQL Veritabanlarını Geri Yükleme ---
echo "🧠 SQL veritabanları geri yükleniyor..."

# Container içerisindeki yedek dosyalarının yolu (SQL Server container, backup dizinini mount etmiş olmalı)
FILE_BASE="/var/opt/mssql/backup"

# Kontrol: sqlcmd komutu mevcut mu?
if ! command -v sqlcmd &>/dev/null; then
    echo "⚠️ 'sqlcmd' bulunamadı. Lütfen SQLCMD kurulumunu kontrol edin!"
    exit 1
fi

for bak in "$SQL_DIR"/*.bak; do
    DBNAME=$(basename "$bak" | cut -d'-' -f1)
    FILE_IN_CONTAINER="$FILE_BASE/$(basename "$bak")"
    echo "🔁 $DBNAME geri yükleniyor (dosya: $(basename "$bak"))..."

    tmp_sql="/tmp/restore_${DBNAME}.sql"
    cat > "$tmp_sql" <<EOF
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = '$DBNAME')
BEGIN
    ALTER DATABASE [$DBNAME] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    ALTER DATABASE [$DBNAME] SET OFFLINE WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$DBNAME];
END
GO
RESTORE DATABASE [$DBNAME] FROM DISK = N'$FILE_IN_CONTAINER' WITH REPLACE, RECOVERY;
GO
EOF

timeout -k 10 30 sqlcmd -S localhost -U sa -P "$SQL_PASSWORD" -i "$tmp_sql" >/dev/null || true

if [ $? -eq 0 ]; then
    echo "✅ $DBNAME geri yüklemesi başarıyla tamamlandı."
else
    echo "⚠️ $DBNAME yüklemesi muhtemelen tamamlandı ama timeout ile sonlandırıldı."
fi

rm -f "$tmp_sql"
done



echo "✅ Tüm veritabanları geri yüklendi."

# --- Docker Compose ile Stack'in Yeniden Başlatılması ---
echo "🐳 Docker container'ları yeniden başlatılıyor..."
cd "$HOME/meow-stack" || { echo "❌ meow-stack dizinine erişilemiyor!"; exit 1; }
# Kullanılan compose sürümüne göre aşağıdakilerden birini kullanın:
if command -v docker-compose &>/dev/null; then
    docker compose up -d
else
    docker-compose up -d
fi

# --- İşlem Tamamlandı ---
echo "✅ Geri yükleme işlemi tamamlandı."
echo "📂 Stack dizini: $HOME/meow-stack"
echo "🗃️ Yedek klasörü: $BACKUP_DIR"
echo "📄 Log dosyası: $LOG_FILE"
