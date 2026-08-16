# Operations

## Status

```bash
systemctl status timetv-backend nginx postgresql redis-server --no-pager
```

## Logs

```bash
journalctl -u timetv-backend -f
journalctl -u nginx -f
journalctl -u postgresql -f
journalctl -u redis-server -f
```

## Backend update

```bash
sudo ./scripts/update_native_backend.sh
```

## Live provider acceptance

```bash
cd /opt/timetv/backend
set -a; source /etc/timetv/timetv.env; set +a
PYTHONPATH=/opt/timetv/backend /opt/timetv/venv/bin/python \
  /path/to/project/scripts/check_tmdb_live.py Interstellar
```

## Backup

```bash
sudo BACKUP_DIR=/srv/backups/cinetrack ./scripts/backup.sh
```

Back up PostgreSQL plus `/var/lib/timetv/uploads` (avatars + poster cache). Poster cache can be regenerated; user uploads/database cannot.

## Restore

```bash
sudo ./scripts/restore.sh /path/to/postgres.dump /path/to/uploads.tar.gz
```

## Database

```bash
sudo -u postgres psql -d timetv
sudo -u postgres pg_isready
```

## Redis

```bash
redis-cli PING
redis-cli INFO memory
```

Do not routinely flush Redis in production; it is useful fallback cache.

## Credential rotation

Rotate the credential in TMDB, then:

```bash
sudo ./scripts/configure_tmdb.sh /etc/timetv/timetv.env
sudo systemctl restart timetv-backend
```

Run the live acceptance test afterward.
