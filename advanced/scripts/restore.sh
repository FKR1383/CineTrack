#!/usr/bin/env bash
set -euo pipefail
[[ "$#" -ge 1 ]] || { echo "Usage: $0 <postgres.dump> [uploads.tar.gz]" >&2; exit 2; }
ENV_FILE="${ENV_FILE:-/etc/timetv/timetv.env}"
DB_DUMP="$(realpath "$1")"
UPLOAD_ARCHIVE="${2:-}"
[[ -s "$DB_DUMP" ]] || { echo "Missing/empty dump: $DB_DUMP" >&2; exit 1; }
[[ "${CONFIRM_RESTORE:-}" == "YES" ]] || { echo 'Set CONFIRM_RESTORE=YES to replace current data.' >&2; exit 1; }
set -a; source "$ENV_FILE"; set +a
DB_NAME="${POSTGRES_DB:-timetv}"; DB_USER="${POSTGRES_USER:-timetv}"
systemctl stop timetv-backend
sudo -u postgres dropdb --if-exists --force "$DB_NAME"
sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"
# The postgres OS user cannot traverse /root. Copy the dump to a private
# temporary file that it can read, mirroring the safe manual migration flow.
RESTORE_TMP="$(mktemp /tmp/cinetrack-restore-XXXXXX.dump)"
cp "$DB_DUMP" "$RESTORE_TMP"
chown postgres:postgres "$RESTORE_TMP"
chmod 600 "$RESTORE_TMP"
trap 'rm -f "$RESTORE_TMP"' EXIT
sudo -u postgres pg_restore --no-owner --role="$DB_USER" -d "$DB_NAME" "$RESTORE_TMP"
if [[ -n "$UPLOAD_ARCHIVE" ]]; then
  UPLOAD_ARCHIVE="$(realpath "$UPLOAD_ARCHIVE")"
  rm -rf /var/lib/timetv/uploads/*
  tar -xzf "$UPLOAD_ARCHIVE" -C /var/lib/timetv/uploads
  chown -R timetv:timetv /var/lib/timetv/uploads
fi
systemctl start timetv-backend
echo 'Restore completed.'
