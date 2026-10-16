#!/usr/bin/env bash
set -e

echo "=========================================================="
echo "  CÀI ĐẶT HỆ SINH THÁI 3 PHẦN MỀM XÂY DỰNG - KS. TRẦN DƯƠNG KHÁNH"
echo "  Hệ điều hành: Ubuntu Linux (Cloud Server iNET)"
echo "  Domain: khanhtran.io.vn"
echo "=========================================================="

# 1. Cập nhật hệ thống
echo ">>> [1/7] Cập nhật Ubuntu package..."
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y curl git ufw nginx python3 python3-pip python3-venv certbot python3-certbot-nginx

# 2. Cài đặt Node.js v22 (cho phần mềm Kho Vật Liệu)
echo ">>> [2/7] Cài đặt Node.js v22..."
if ! command -v node &> /dev/null || [ "$(node -v | cut -d'.' -f1 | tr -d 'v')" -lt 22 ]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt install -y nodejs
fi
echo "Node.js: $(node -v) | NPM: $(npm -v)"

# 3. Cài đặt PM2 quản lý tiến trình ngầm 24/7
echo ">>> [3/7] Cài đặt PM2..."
npm install -g pm2

# 4. Chuẩn bị thư mục ứng dụng
echo ">>> [4/7] Thiết lập thư mục ứng dụng..."
mkdir -p /var/www/kho-vatlieu
mkdir -p /var/www/crm-xaydung
mkdir -p /var/www/pm-luong

# Tải mã nguồn Kho Vật Liệu nếu chưa có
if [ ! -d "/var/www/kho-vatlieu/.git" ]; then
  git clone https://github.com/khanh1276-art/ql-vatlieu-congtruong.git /var/www/kho-vatlieu || true
else
  cd /var/www/kho-vatlieu && git pull origin main || true
fi

# Tải mã nguồn CRM Xây Dựng nếu chưa có
if [ ! -d "/var/www/crm-xaydung/.git" ]; then
  git clone https://github.com/khanh1276-art/crm-construction.git /var/www/crm-xaydung || true
else
  cd /var/www/crm-xaydung && git pull origin main || true
fi

# Cài đặt môi trường Python cho CRM
if [ -d "/var/www/crm-xaydung" ]; then
  cd /var/www/crm-xaydung
  python3 -m venv venv || true
  ./venv/bin/pip install --upgrade pip
  ./venv/bin/pip install -r requirements.txt || true
fi

# 5. Cấu hình Nginx điều hướng 3 Subdomain
echo ">>> [5/7] Cấu hình Nginx Virtual Hosts..."
cat << 'EOF' > /etc/nginx/sites-available/khanhtran-ecosystem
# 1. KHO VẬT LIỆU (Port 3000)
server {
    listen 80;
    server_name kho.khanhtran.io.vn;
    client_max_body_size 50M;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# 2. CRM XÂY DỰNG (Port 8088)
server {
    listen 80;
    server_name crm.khanhtran.io.vn;
    client_max_body_size 50M;

    location / {
        proxy_pass http://127.0.0.1:8088;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# 3. PM LƯƠNG XÂY DỰNG (Port 8000)
server {
    listen 80;
    server_name luong.khanhtran.io.vn;
    client_max_body_size 50M;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

ln -sf /etc/nginx/sites-available/khanhtran-ecosystem /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx

# 6. Khởi động các dịch vụ bằng PM2
echo ">>> [6/7] Khởi động các phần mềm với PM2..."
# Khởi động Kho Vật Liệu
if [ -f "/var/www/kho-vatlieu/src/server.js" ]; then
  cd /var/www/kho-vatlieu
  pm2 delete kho-vatlieu 2>/dev/null || true
  pm2 start src/server.js --name "kho-vatlieu"
fi

# Khởi động CRM Xây Dựng
if [ -f "/var/www/crm-xaydung/run.py" ]; then
  cd /var/www/crm-xaydung
  pm2 delete crm-xaydung 2>/dev/null || true
  pm2 start "./venv/bin/python3 run.py --port 8088" --name "crm-xaydung"
fi

# Khởi động PM Lương (khi có file app.py)
if [ -f "/var/www/pm-luong/app.py" ]; then
  cd /var/www/pm-luong
  pm2 delete pm-luong 2>/dev/null || true
  pm2 start "./venv/bin/uvicorn app:app --host 127.0.0.1 --port 8000" --name "pm-luong"
fi

pm2 save
pm2 startup systemd -u root --hp /root || true

# 7. Mở Firewall (UFW)
echo ">>> [7/7] Thiết lập tường lửa..."
ufw allow 22/tcp || true
ufw allow 80/tcp || true
ufw allow 443/tcp || true
echo "y" | ufw enable || true

echo ""
echo "=========================================================="
echo "  🎉 THIẾT LẬP MÔI TRƯỜNG THÀNH CÔNG!"
echo "  Các cổng dịch vụ đã sẵn sàng:"
echo "  👉 Kho Vật Liệu:   http://kho.khanhtran.io.vn (Port 3000)"
echo "  👉 CRM Xây Dựng:   http://crm.khanhtran.io.vn (Port 8088)"
echo "  👉 PM Lương:       http://luong.khanhtran.io.vn (Port 8000)"
echo "=========================================================="
