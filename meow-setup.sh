# Dosya yapısını oluştur
mkdir meow-setup && cd meow-setup

echo "🚧 Dosyalar oluşturuluyor..."

# Kurulum scriptini oluştur
cat > meow-setup.sh <<'EOF'
#!/bin/bash

# ========== MEOW SETUP SCRIPT ==========
echo "\n🐾 MEOW VPS OTOMATIK KURULUM BAŞLIYOR..."

# === Kullanıcıdan bilgi al ===
echo "\n🌐 Lütfen Docker ağı için bir network adı girin (örnek: vps_network):"
read -rp "> " network_name

echo "\n🛡️  Lütfen SQL Server için bir şifre belirleyin (örnek: M30w1903Database):"
read -rsp "> " db_password

echo "\n🔐 Lütfen SSH port numarasını girin (örnek: 2510):"
read -rp "> " ssh_port

echo "\n📧 Lütfen varsayılan e-posta adresinizi girin (örnek: admin@beratoksz.com):"
read -rp "> " default_email

echo "\n🌍 Lütfen test etmek istediğiniz domain adresini girin (örnek: test.beratoksz.com):"
read -rp "> " test_domain

echo "\n\n🔧 Network adı: $network_name"
echo "🔑 SQL Server şifresi: ********"
echo "🛡️  SSH Portu: $ssh_port"
echo "📧 E-posta: $default_email"
echo "🌍 Test Domain: $test_domain"
echo "\nKuruluma başlamak için ENTER'a basın..."
read

# === Sistem Güncelleme & Gerekli Paketler ===
echo "\n📦 Gerekli paketler kuruluyor..."
sudo apt update && sudo apt install -y docker.io docker-compose ufw curl git zsh dnsutils apt-transport-https ca-certificates gnupg software-properties-common
sudo usermod -aG docker "$USER"

# === Firewall Ayarları ===
echo "\n🧱 Güvenlik duvarı yapılandırılıyor..."
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow "$ssh_port"/tcp
sudo ufw --force enable

# === Oh My Zsh Kurulumu ===
echo "\n💅 ZSH kuruluyor..."
chsh -s $(which zsh)
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# === Docker Network Oluştur ===
echo "\n🔌 Docker ağı oluşturuluyor: $network_name"
docker network create "$network_name"

# === Nginx Proxy Stack Kurulumu ===
echo "\n🌐 Nginx Reverse Proxy kuruluyor..."
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
echo "\n🧠 SQL Server kuruluyor..."
docker run -d \
  --name sqlserver \
  -e 'ACCEPT_EULA=Y' \
  -e "SA_PASSWORD=$db_password" \
  -p 1433:1433 \
  -v sql_data:/var/opt/mssql \
  --network $network_name \
  mcr.microsoft.com/mssql/server:2022-latest

# === SQLCMD Kurulumu ===
echo "\n🛠️ SQL komut aracı (sqlcmd) kuruluyor..."
curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
sudo add-apt-repository "$(wget -qO- https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list)"
sudo apt update
sudo apt install -y mssql-tools unixodbc-dev

# PATH'e ekle
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.zshrc
source ~/.zshrc

# === Domain Testi ===
echo "\n🔎 Domain yönlendirmesi kontrol ediliyor: $test_domain"
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
echo "\n🔐 SSL sertifikası test ediliyor..."
sleep 5
curl -s --head "https://$test_domain" | grep -i "strict-transport-security" && echo "✅ SSL sertifikası aktif." || echo "⚠️  SSL aktif değil veya yönlendirme eksik."

# === Tamamlandı ===
echo "\n✅ Kurulum tamamlandı!"
echo "📁 Nginx stack dizini: ~/meow-stack"
echo "📡 Docker ağı: $network_name"
echo "🛢️  SQL Server şifresi: $db_password"
echo "🛡️  SSH Portu: $ssh_port"
echo "📧 Default E-posta: $default_email"

# === Hatırlatma ===
echo "\n⚠️  UYARI: Modeminizin ya da VPS sağlayıcınızın panelinde aşağıdaki portların açık olduğundan emin olun:"
echo "   - HTTP: 80/tcp"
echo "   - HTTPS: 443/tcp"
echo "   - MSSQL: 1433/tcp"
echo "   - SSH: $ssh_port/tcp"
echo "\nAksi halde SSL alma, dış bağlantılar ve yönetim erişimi çalışmayabilir."
echo "\n🚀 Şimdi projeni deploy etmeye hazırsın!"

EOF

# README dosyasını oluştur
cat > README.md <<'EOF'
# 🐾 Meow Setup

Bu script ile Ubuntu VPS sunucunuzu tek komutla aşağıdaki şekilde kurabilirsiniz:

- Docker & Docker Compose kurulumu
- UFW ile port açma (80, 443, 1433, SSH)
- Nginx + Let's Encrypt reverse proxy
- SQL Server (Docker ile)
- SQLCMD Aracı
- ZSH + Oh My Zsh kurulumu
- Domain yönlendirme ve SSL testi

## 🚀 Kullanım

```bash
bash <(curl -sSL https://raw.githubusercontent.com/kullaniciadi/meow-setup/main/meow-setup.sh)
```

## 🔐 Gerekli Portlar
- HTTP: 80/tcp
- HTTPS: 443/tcp
- SQL Server: 1433/tcp
- SSH: sizin belirlediğiniz port

## ✍️ Kurulumda Sorulacak Bilgiler
- Docker Network Adı
- SQL Server Şifresi
- SSH Portu
- Default Email
- Test Domain (SSL kontrolü için)

---

✨ Daha fazla bilgi için bu repo güncellenecektir.
EOF

# Scripti çalıştırılabilir yap
chmod +x meow-setup.sh

echo "✅ Repo hazır. Şimdi Git işlemlerine geçebilirsin."
echo "📦 Şu komutlarla GitHub'a atabilirsin:"
echo ""
echo "git init"
echo "git remote add origin https://github.com/<kullanici-adi>/meow-setup.git"
echo "git add ."
echo "git commit -m 'Initial commit - Meow setup script'"
echo "git branch -M main"
echo "git push -u origin main"
echo ""
echo "🔥 Push sonrası direkt kurulum için kullanabileceğin komut:"
echo "bash <(curl -sSL https://raw.githubusercontent.com/<kullanici-adi>/meow-setup/main/meow-setup.sh)"

