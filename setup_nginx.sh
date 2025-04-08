#!/bin/bash
# setup_nginx.sh - Nginx'i kurar ve düzenleme kısayolu ekler.

set -e

# 1. Nginx'in kurulu olup olmadığını kontrol et, yoksa kur.
if ! command -v nginx &> /dev/null; then
  echo "Nginx bulunamadı, kuruluyor..."
  # Bu örnek Debian/Ubuntu tabanlı sistemler için. Diğer dağıtımlarda paket yöneticini kullan.
  sudo apt update && sudo apt install -y nginx
else
  echo "Nginx zaten kurulu."
fi

# 2. Alias ekle: edit_nginx komutu /etc/nginx/nginx.conf dosyasını açacak.
ALIAS_CMD="alias edit_nginx='sudo nano /etc/nginx/nginx.conf'"

# Alias zaten eklenmiş mi kontrol edelim:
if ! grep -q "alias edit_nginx=" ~/.bashrc; then
  echo "Alias ekleniyor: edit_nginx"
  echo "$ALIAS_CMD" >> ~/.bashrc
  echo "Alias eklendi. Değişikliklerin aktif olabilmesi için terminali yeniden başlat veya 'source ~/.bashrc' komutunu çalıştır."
else
  echo "Alias zaten mevcut: edit_nginx"
fi

echo "Nginx kurulumu ve alias ayarı tamamlandı."
