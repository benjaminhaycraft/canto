#!/bin/bash
# ============================================================
# Canto API — Deploy / Update
# Run from your LOCAL machine to push code to the VPS:
#   bash deploy/02-deploy.sh
#
# Or from the VPS itself:
#   bash deploy/02-deploy.sh --local
# ============================================================

set -euo pipefail

VPS_HOST="${CANTO_VPS:-root@YOUR_VPS_IP}"
VPS_USER="canto"
APP_DIR="/home/$VPS_USER/canto-api"
LOCAL_MODE="${1:-}"

echo ""
echo "  🚀 Deploying Canto API..."
echo ""

if [ "$LOCAL_MODE" = "--local" ]; then
  # ──── Running directly on VPS ────
  echo "[1/4] Already on server, skipping upload..."

  echo "[2/4] Installing dependencies..."
  cd "$APP_DIR"
  npm ci --omit=dev

  echo "[3/4] Running database migrations..."
  node scripts/migrate.js

  echo "[4/4] Restarting application..."
  pm2 describe canto-api > /dev/null 2>&1 && pm2 restart canto-api || {
    pm2 start src/server.js --name canto-api --cwd "$APP_DIR" \
      --max-memory-restart 300M \
      --log-date-format "YYYY-MM-DD HH:mm:ss" \
      --merge-logs
    pm2 save
    pm2 startup systemd -u $VPS_USER --hp /home/$VPS_USER 2>/dev/null || true
  }

else
  # ──── Running from local machine ────
  echo "[1/4] Uploading code to $VPS_HOST..."
  rsync -avz --delete \
    --exclude node_modules \
    --exclude .env \
    --exclude .git \
    ./ "$VPS_HOST:$APP_DIR/"

  echo "[2/4] Setting permissions..."
  ssh "$VPS_HOST" "chown -R $VPS_USER:$VPS_USER $APP_DIR"

  echo "[3/4] Installing deps + running migrations..."
  ssh "$VPS_HOST" "sudo -u $VPS_USER bash -c 'cd $APP_DIR && npm ci --omit=dev && node scripts/migrate.js'"

  echo "[4/4] Restarting application..."
  ssh "$VPS_HOST" "sudo -u $VPS_USER bash -c 'cd $APP_DIR && pm2 describe canto-api > /dev/null 2>&1 && pm2 restart canto-api || pm2 start src/server.js --name canto-api --max-memory-restart 300M --log-date-format \"YYYY-MM-DD HH:mm:ss\" --merge-logs && pm2 save'"
fi

echo ""
echo "  ✅ Deploy complete!"
echo ""

# Quick health check
sleep 2
if [ "$LOCAL_MODE" = "--local" ]; then
  curl -sf http://localhost:3001/api/health && echo "" || echo "  ⚠ Health check failed — check pm2 logs"
else
  ssh "$VPS_HOST" "curl -sf http://localhost:3001/api/health" && echo "" || echo "  ⚠ Health check failed — run: ssh $VPS_HOST 'pm2 logs canto-api'"
fi
