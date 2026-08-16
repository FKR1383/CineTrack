#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$ROOT_DIR/backups}"
ENV_FILE="${ENV_FILE:-/etc/timetv/timetv.env}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }
mkdir -p "$BACKUP_DIR"
set -a; source "$ENV_FILE"; set +a
DB_NAME="${POSTGRES_DB:-timetv}"
DB_USER="${POSTGRES_USER:-timetv}"
PGPASSWORD="${POSTGRES_PASSWORD:-}" pg_dump -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -Fc > "$BACKUP_DIR/postgres-$STAMP.dump"
tar -czf "$BACKUP_DIR/uploads-$STAMP.tar.gz" -C /var/lib/timetv/uploads .
sha256sum "$BACKUP_DIR/postgres-$STAMP.dump" "$BACKUP_DIR/uploads-$STAMP.tar.gz" > "$BACKUP_DIR/sha256-$STAMP.txt"
find "$BACKUP_DIR" -type f -mtime +"${BACKUP_RETENTION_DAYS:-30}" -delete
echo "Backup written to $BACKUP_DIR"
