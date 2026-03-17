#!/bin/bash
# Install the 'canto' CLI command on the VPS
# Run once: bash deploy/04-install-cli.sh

set -euo pipefail

CLI_PATH="/usr/local/bin/canto"
SOURCE="$(dirname "$0")/canto"

cp "$SOURCE" "$CLI_PATH"
chmod +x "$CLI_PATH"

echo "✔ 'canto' command installed. Try: canto status"

# Set up daily backup cron if not exists
CRON_LINE="0 3 * * * /home/canto/canto-api/deploy/03-backup.sh >> /home/canto/backups/backup.log 2>&1"
(crontab -l 2>/dev/null | grep -v "03-backup.sh"; echo "$CRON_LINE") | crontab -
echo "✔ Daily backup scheduled at 3:00 AM"

# Set up weekly SSL renewal
SSL_CRON="0 4 * * 0 certbot renew --quiet && systemctl reload nginx"
(crontab -l 2>/dev/null | grep -v "certbot renew"; echo "$SSL_CRON") | crontab -
echo "✔ Weekly SSL renewal scheduled"

echo ""
echo "Cron jobs active:"
crontab -l | grep -v "^#" | sed 's/^/  /'
