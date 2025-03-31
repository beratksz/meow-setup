#!/bin/bash

# ========== MEOW SETUP SCRIPT ==========
echo -e "\n🐾 MEOW VPS OTOMATIK KURULUM BAŞLIYOR..."

# === Kullanıcıdan bilgi al ===
echo -e "\n🌐 Lütfen Docker ağı için bir network adı girin (örnek: vps_network):"
read -rp "> " network_name

echo -e "\n🛡️  Lütfen SQL Server için bir şifre belirleyin (örnek: M30w1903Database):"
read -rsp "> " db_password

echo -e "\n🔐 Lütfen SSH port numarasını girin (örnek: 2510):"
read -rp "> " ssh_port

echo -e "\n📧 Lütfen varsayılan e-posta adresinizi girin (örnek: admin@beratoksz.com):"
read -rp "> " default_email

echo -e "\n🌍 Lütfen test etmek istediğiniz domain adresini girin (örnek: test.beratoksz.com):"
read -rp "> " test_domain

# Bilgileri göster
echo -e "\n\n🔧 Network adı: $network_name"
echo "🔑 SQL Server şifresi: ********"
echo "🛡️  SSH Portu: $ssh_port"
echo "📧 E-posta: $default_email"
echo "🌍 Test Domain: $test_domain"
echo -e "\nKuruluma başlamak için ENTER'a basın..."
read

# Log dosyası
exec > >(tee -i install.log)
exec 2>&1

# === Sistem Güncelleme & Gerekli Paketler ===
echo -e "\n📦 Gerekli paketler kuruluyor..."
sudo apt update && sudo apt install -y docker.io docker-compose ufw curl git zsh dnsutils apt-transport-https ca-certificates gnupg software-properties-common
sudo usermod -aG docker "$USER"

# === Firewall Ayarları ===
echo -e "\n🧱 Güvenlik duvarı yapılandırılıyor..."
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow "$ssh_port"/tcp
sudo ufw --force enable

# === Oh My Zsh Kurulumu ===
echo -e "\n💅 ZSH kuruluyor..."
chsh -s $(which zsh)
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# === Docker Network Oluştur ===
echo -e "\n🔌 Docker ağı oluşturuluyor: $network_name"
docker network inspect "$network_name" >/dev/null 2>&1 || docker network create "$network_name"

# === Nginx Proxy Stack Kurulumu ===
echo -e "\n🌐 Nginx Reverse Proxy kuruluyor..."
mkdir -p ~/meow-stack && cd ~/meow-stack || exit

cat > docker-compose.yml <<EOF2
version: '3.8'

services:
  nginx-proxy:
    image: jwilder/nginx-proxy
    container_name: nginx-proxy
    restart: always
    networks:
      - $network_name
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
      - $network_name
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./certs:/etc/nginx/certs
      - ./acme:/etc/acme.sh
      - ./vhost.d:/etc/nginx/vhost.d
      - ./html:/usr/share/nginx/html
    environment:
      DEFAULT_EMAIL: $default_email

networks:
  $network_name:
    external: true
EOF2

docker-compose up -d

# === SQL Server Kurulumu ===
echo -e "\n🧠 SQL Server kuruluyor..."
docker volume inspect sql_data >/dev/null 2>&1 || docker volume create sql_data
docker run -d \
  --name sqlserver \
  -e 'ACCEPT_EULA=Y' \
  -e "SA_PASSWORD=$db_password" \
  -p 1433:1433 \
  -v sql_data:/var/opt/mssql \
  --network $network_name \
  mcr.microsoft.com/mssql/server:2022-latest

# === SQLCMD Kurulumu ===
echo -e "\n🛠️ SQL komut aracı (sqlcmd) kuruluyor..."
curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
curl -sSL https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
sudo apt update
sudo ACCEPT_EULA=Y apt install -y mssql-tools unixodbc-dev

echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.zshrc
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
source ~/.zshrc || true

# === SQL Test ===
echo -e "\n🧪 SQL Server bağlantısı test ediliyor..."
/opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P "$db_password" -Q "SELECT @@VERSION;" || echo "⚠️  SQL Server bağlantı hatası!"

# === Domain Testi ===
echo -e "\n🔎 Domain yönlendirmesi kontrol ediliyor: $test_domain"
resolved_ip=$(dig +short "$test_domain")
public_ip=$(curl -s ifconfig.me)

if [[ "$resolved_ip" == "$public_ip" ]]; then
  echo "✅ Domain doğru şekilde VPS IP'sine yönlenmiş ($resolved_ip)"
else
  echo "❌ Domain IP eşleşmiyor! DNS yönlendirmesini kontrol edin."
  echo "   - $test_domain --> $resolved_ip"
  echo "   - VPS IP        --> $public_ip"
fi

# === SSL Sertifikası Kontrolü ===
echo -e "\n🔐 SSL sertifikası test ediliyor..."
sleep 2
curl -s --max-time 5 --head "https://$test_domain" | grep -i "strict-transport-security" && echo "✅ SSL sertifikası aktif." || echo "⚠️  SSL aktif değil veya yönlendirme eksik."

# === Bilgi Dosyası ===
echo -e "\n📄 setup.env dosyası oluşturuluyor..."
echo -e "SA_PASSWORD=\"$db_password\"\nSSH_PORT=\"$ssh_port\"\nEMAIL=\"$default_email\"" > ~/meow-stack/setup.env

# === Tamamlandı ===
echo -e "\n✅ Kurulum tamamlandı!"
echo "📁 Nginx stack dizini: ~/meow-stack"
echo "📡 Docker ağı: $network_name"
echo "🛢️  SQL Server şifresi: $db_password"
echo "🛡️  SSH Portu: $ssh_port"
echo "📧 Default E-posta: $default_email"

echo -e "\n⚠️  UYARI: Modeminizin ya da VPS sağlayıcınızın panelinde aşağıdaki portların açık olduğundan emin olun:"
echo "   - HTTP: 80/tcp"
echo "   - HTTPS: 443/tcp"
echo "   - MSSQL: 1433/tcp"
echo "   - SSH: $ssh_port/tcp"
echo -e "\nAksi halde SSL alma, dış bağlantılar ve yönetim erişimi çalışmayabilir."
echo -e "\n🚀 Şimdi projeni deploy etmeye hazırsın!"
