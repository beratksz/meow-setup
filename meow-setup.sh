#!/bin/bash
# ========== MEOW VPS OTOMATIK KURULUM SCRIPTİ ==========

set -euo pipefail

echo -e "\n🐾 MEOW VPS OTOMATIK KURULUM BAŞLIYOR..."

# === Kullanıcıdan Bilgileri Al ===
echo -e "\n🌐 Docker ağı için bir network adı girin (örnek: vps_network):"
read -rp "> " network_name

echo -e "\n🛡️  SQL Server için bir şifre belirleyin (örnek: M30w1903Database):"
read -rsp "> " db_password
echo

echo -e "\n🔐 SSH port numarasını girin (örnek: 2510):"
read -rp "> " ssh_port

echo -e "\n📧 Varsayılan e-posta adresinizi girin (örnek: admin@ornek.com):"
read -rp "> " default_email

echo -e "\n🌍 Test etmek istediğiniz domain adresini girin (örnek: test.ornek.com):"
read -rp "> " test_domain

# Girdileri Göster (Şifre gizli)
echo -e "\n🔧 Girdiğiniz Bilgiler:"
echo "   - Docker Network: $network_name"
echo "   - SQL Server Şifresi: ********"
echo "   - SSH Port: $ssh_port"
echo "   - E-posta: $default_email"
echo "   - Test Domain: $test_domain"
echo -e "\nKuruluma başlamak için ENTER'a basın..."
read

# Loglama: Hassas bilgilerin loglanmamasına özen gösterin!
exec > >(tee -i install.log)
exec 2>&1

# === Sistem Güncelleme & Gerekli Paketlerin Kurulması ===
echo -e "\n📦 Sistem güncelleniyor ve gerekli paketler kuruluyor..."
sudo apt-get update

# Docker'ın eski sürümleri kaldırılıyor
sudo apt-get remove -y docker docker-engine docker.io containerd runc || true

# Gerekli paketlerin kurulumu (bazıları zaten sisteminizde olabilir)
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release ufw git zsh dnsutils software-properties-common

# === Docker'ın Güncel Sürümünün Kurulumu ===
echo -e "\n🚀 Docker'ın güncel sürümü kuruluyor..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Kullanıcıyı Docker grubuna ekleyin (Değişikliğin etkili olması için oturumu yenileyin)
sudo usermod -aG docker "$USER"
echo -e "\nℹ️  'newgrp docker' komutunu çalıştırın veya oturumu kapatıp açın."

# === Güvenlik Duvarı (UFW) Yapılandırması ===
echo -e "\n🧱 Güvenlik duvarı yapılandırılıyor..."
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow "$ssh_port"/tcp
sudo ufw --force enable

# === Docker Network Oluşturulması ===
echo -e "\n🔌 Docker ağı oluşturuluyor: $network_name"
if ! docker network inspect "$network_name" >/dev/null 2>&1; then
    docker network create "$network_name"
fi

# === Nginx Reverse Proxy Stack Kurulumu ===
echo -e "\n🌐 Nginx Reverse Proxy ve Let's Encrypt kurulumu başlatılıyor..."
mkdir -p ~/meow-stack && cd ~/meow-stack || { echo "❌ ~/meow-stack dizinine erişilemedi!"; exit 1; }

cat > docker-compose.yml <<EOF
version: '3.8'

services:
  nginx-proxy:
    image: jwilder/nginx-proxy
    container_name: nginx-proxy
    restart: always
    networks:
      - ${network_name}
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock:ro
      - ./certs:/etc/nginx/certs
      - ./vhost.d:/etc/nginx/vhost.d
      - ./html:/usr/share/nginx/html

  nginx-proxy-letsencrypt:
    image: jrcs/letsencrypt-nginx-proxy-companion
    container_name: nginx-proxy-letsencrypt
    restart: always
    depends_on:
      - nginx-proxy
    networks:
      - ${network_name}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./certs:/etc/nginx/certs
      - ./acme:/etc/acme.sh
      - ./vhost.d:/etc/nginx/vhost.d
      - ./html:/usr/share/nginx/html
    environment:
      DEFAULT_EMAIL: ${default_email}
      NGINX_PROXY_CONTAINER: "nginx-proxy"

networks:
  ${network_name}:
    external: true
EOF

docker compose up -d

# === rclone Kurulumu (otomatik) ===
echo -e "\n☁️  rclone kurulumu kontrol ediliyor..."
if ! command -v rclone &>/dev/null; then
    echo "rclone bulunamadı, kuruluyor..."
    curl https://rclone.org/install.sh | sudo bash
else
    echo "✅ rclone zaten yüklü."
fi

# === SQL Server Kurulsun mu? ===
read -rp $'\n🧠 SQL Server kurulacak mı? (yes/no): ' install_sqlserver

if [[ "$install_sqlserver" == "yes" ]]; then
    echo -e "\n🧠 SQL Server Docker konteyneri kuruluyor..."
    mkdir -p "$HOME/meow-backup/sql"
    docker volume inspect sql_data >/dev/null 2>&1 || docker volume create sql_data
    docker run -d \
      --name sqlserver \
      -e 'ACCEPT_EULA=Y' \
      -e "SA_PASSWORD=${db_password}" \
      -p 1433:1433 \
      -v sql_data:/var/opt/mssql \
      -v "$HOME/meow-backup/sql":/var/opt/mssql/backup \
      --network ${network_name} \
      mcr.microsoft.com/mssql/server:2022-latest

    echo "SQL Server'ın tamamen başlatılması için 30 saniye bekleniyor..."
    sleep 30

    # SQLCMD Kurulumu
    echo -e "\n🛠️ SQL komut aracı (sqlcmd) kuruluyor..."
    curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
    curl -sSL https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
    sudo apt-get update
    sudo ACCEPT_EULA=Y apt-get install -y mssql-tools unixodbc-dev

    echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
    source ~/.bashrc || true

    echo -e "\n🧪 SQL Server bağlantısı test ediliyor..."
    /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P "${db_password}" -Q "SELECT @@VERSION;" || echo "⚠️  SQL Server bağlantı hatası!"
else
    echo "⏭️  SQL Server kurulumu atlandı."
fi


# === Domain Yönlendirme Testi ===
echo -e "\n🔎 Domain yönlendirmesi kontrol ediliyor: ${test_domain}"
resolved_ip=$(dig +short "${test_domain}")
public_ip=$(curl -s ifconfig.me)
if [[ "${resolved_ip}" == "${public_ip}" ]]; then
  echo "✅ Domain doğru şekilde VPS IP'sine yönlenmiş: ${resolved_ip}"
else
  echo "❌ Domain IP eşleşmiyor! Lütfen DNS yönlendirmesini kontrol edin."
  echo "   - ${test_domain} --> ${resolved_ip}"
  echo "   - VPS IP      --> ${public_ip}"
fi

# === SSL Sertifikası Testi ===
echo -e "\n🔐 SSL sertifikası kontrol ediliyor..."
sleep 2
curl -s --max-time 5 --head "https://${test_domain}" | grep -i "strict-transport-security" && echo "✅ SSL sertifikası aktif." || echo "⚠️  SSL aktif değil veya yönlendirme eksik."

# === Bilgi Dosyası Oluşturulması ===
echo -e "\n📄 setup.env dosyası oluşturuluyor..."
cat > setup.env <<EOL
SA_PASSWORD="${db_password}"
SSH_PORT="${ssh_port}"
EMAIL="${default_email}"
EOL

# === Kurulum Tamamlandı Mesajı ===
echo -e "\n✅ Kurulum tamamlandı!"
echo "📁 Nginx stack dizini: ~/meow-stack"
echo "📡 Docker ağı: ${network_name}"
echo "🛢️  SQL Server şifresi: ******** (setup.env dosyasında saklanıyor)"
echo "🛡️  SSH Portu: ${ssh_port}"
echo "📧 Default E-posta: ${default_email}"
echo -e "\n⚠️  UYARI: VPS sağlayıcınızın panelinde veya modeminizde aşağıdaki portların açık olduğundan emin olun:"
echo "   - HTTP: 80/tcp"
echo "   - HTTPS: 443/tcp"
echo "   - MSSQL: 1433/tcp"
echo "   - SSH: ${ssh_port}/tcp"
echo -e "\n🚀 Şimdi projeni deploy etmeye hazırsın! Unutma, doğru yapılandırma sistemini pürüzsüz çalıştırır; tıpkı iyi yapılandırılmış bir kod gibi!"
