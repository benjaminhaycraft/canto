#!/bin/bash
# ============================================================
# Canto API — Database Backup
# Run on the VPS (manually or via cron):
#   bash /home/canto/canto-api/deploy/03-backup.sh
#
# Auto-setup (daily at 3 AM):
#   crontab -e
#   0 3 * * * /home/canto/canto-api/deploy/03-backup.sh >> /home/canto/backups/backup.log 2>&1
# ============================================================

set -euo pipefail

DB_NAME="canto"
DB_USER="canto"
BACKUP_DIR="/home/canto/backups"
KEEP_DAYS=14

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME="canto_${TIMESTAMP}.sql.gz"

echo "[$(date -Iseconds)] Starting backup..."

# Dump and compress
sudo -u postgres pg_dump "$DB_NAME" | gzip > "$BACKUP_DIR/$FILENAME"

SIZE=$(du -h "$BACKUP_DIR/$FILENAME" | cut -f1)
echo "  ✔ Backup saved: $BACKUP_DIR/$FILENAME ($SIZE)"

# Clean up old backups
DELETED=$(find "$BACKUP_DIR" -name "canto_*.sql.gz" -mtime +$KEEP_DAYS -delete -print | wc -l)
if [ "$DELETED" -gt 0 ]; then
  echo "  ✔ Cleaned $DELETED backups older than $KEEP_DAYS days"
fi

# Count remaining backups
TOTAL=$(ls -1 "$BACKUP_DIR"/canto_*.sql.gz 2>/dev/null | wc -l)
echo "  ✔ Total backups on disk: $TOTAL"
echo "[$(date -Iseconds)] Backup complete."
