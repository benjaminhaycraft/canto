#!/bin/bash
# ============================================================
# Canto API — Initial VPS Setup (Hostinger KVM1 / Ubuntu 22.04)
# Run once after provisioning your VPS:
#   ssh root@YOUR_VPS_IP
#   bash 01-server-setup.sh
# ============================================================

set -euo pipefail

DOMAIN="${1:-api.canto.run}"
APP_USER="canto"
DB_NAME="canto"
DB_USER="canto"
DB_PASS=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)

echo ""
echo "  ██████╗ █████╗ ███╗   ██╗████████╗ ██████╗ "
echo " ██╔════╝██╔══██╗████╗  ██║╚══██╔══╝██╔═══██╗"
echo " ██║     ███████║██╔██╗ ██║   ██║   ██║   ██║"
echo " ██║     ██╔══██║██║╚██╗██║   ██║   ██║   ██║"
echo " ╚██████╗██║  ██║██║ ╚████║   ██║   ╚██████╔╝"
echo "  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ "
echo ""
echo "  Server Setup for: $DOMAIN"
echo "  ──────────────────────────────────────────────"
echo ""

# ──────────────── System Updates ────────────────
echo "[1/8] Updating system packages..."
apt update && apt upgrade -y
apt install -y curl git ufw fail2ban software-properties-common

# ──────────────── Firewall ────────────────
echo "[2/8] Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
echo "  ✔ Firewall active (SSH + HTTP + HTTPS)"

# ──────────────── Create app user ────────────────
echo "[3/8] Creating application user '$APP_USER'..."
if ! id "$APP_USER" &>/dev/null; then
  adduser --disabled-password --gecos "Canto App" "$APP_USER"
  mkdir -p /home/$APP_USER/.ssh
  cp /root/.ssh/authorized_keys /home/$APP_USER/.ssh/ 2>/dev/null || true
  chown -R $APP_USER:$APP_USER /home/$APP_USER/.ssh
  echo "  ✔ User '$APP_USER' created"
else
  echo "  ✔ User '$APP_USER' already exists"
fi

# ──────────────── Node.js 20 LTS ────────────────
echo "[4/8] Installing Node.js 20 LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
npm install -g pm2
echo "  ✔ Node $(node -v) + npm $(npm -v) + pm2"

# ──────────────── PostgreSQL 16 ────────────────
echo "[5/8] Installing PostgreSQL 16..."
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
apt update
apt install -y postgresql-16 postgresql-client-16

sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" 2>/dev/null || true
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
echo "  ✔ PostgreSQL 16 installed, database '$DB_NAME' ready"

# ──────────────── Nginx ────────────────
echo "[6/8] Installing Nginx..."
apt install -y nginx

cat > /etc/nginx/sites-available/canto << NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;

    # API proxy
    location /api/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 90s;
    }

    # Health check (no auth)
    location /api/health {
        proxy_pass http://127.0.0.1:3001;
    }
}
NGINX_CONF

ln -sf /etc/nginx/sites-available/canto /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
echo "  ✔ Nginx configured for $DOMAIN"

# ──────────────── SSL with Certbot ────────────────
echo "[7/8] Installing SSL certificate..."
apt install -y certbot python3-certbot-nginx
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" || {
  echo "  ⚠ SSL setup failed (DNS may not point here yet). Run manually later:"
  echo "    certbot --nginx -d $DOMAIN"
}

# ──────────────── App Directory + .env ────────────────
echo "[8/8] Setting up application directory..."
APP_DIR="/home/$APP_USER/canto-api"
mkdir -p "$APP_DIR"
chown $APP_USER:$APP_USER "$APP_DIR"

cat > "$APP_DIR/.env" << ENV_FILE
# Canto API — Production Environment
# Generated on $(date -Iseconds)
PORT=3001
NODE_ENV=production
API_URL=https://$DOMAIN
FRONTEND_URL=https://canto.run

# Database
DATABASE_URL=postgresql://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME

# JWT (auto-generated)
JWT_SECRET=$JWT_SECRET
JWT_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=30d

# OAuth (fill these in)
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
SPOTIFY_CLIENT_ID=
SPOTIFY_CLIENT_SECRET=
STRAVA_CLIENT_ID=211688
STRAVA_CLIENT_SECRET=dda369893d1aa2400ba743efe4fe078b7673139b
APPLE_CLIENT_ID=
APPLE_TEAM_ID=
APPLE_KEY_ID=

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX=100
ENV_FILE

chown $APP_USER:$APP_USER "$APP_DIR/.env"
chmod 600 "$APP_DIR/.env"

# ──────────────── Summary ────────────────
echo ""
echo "  ══════════════════════════════════════════════"
echo "  ✅ Server setup complete!"
echo "  ══════════════════════════════════════════════"
echo ""
echo "  Domain:     $DOMAIN"
echo "  App user:   $APP_USER"
echo "  App dir:    $APP_DIR"
echo "  Database:   $DB_NAME (user: $DB_USER)"
echo "  DB pass:    $DB_PASS"
echo "  JWT secret: (in .env)"
echo ""
echo "  ⚠  SAVE the DB password above — it won't be shown again."
echo ""
echo "  Next step: run 02-deploy.sh from your local machine"
echo ""
