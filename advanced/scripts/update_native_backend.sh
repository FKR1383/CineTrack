#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-/etc/timetv/timetv.env}"
[[ "$EUID" -eq 0 ]] || exec sudo --preserve-env=ENV_FILE bash "$0" "$@"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }
[[ -d /opt/timetv/venv ]] || { echo 'Native backend is not installed yet; use deploy_native_ubuntu.sh.' >&2; exit 1; }

mkdir -p /opt/timetv/backend /var/lib/timetv/uploads
rsync -a --delete --exclude '.env' --exclude '__pycache__' "$ROOT_DIR/backend/" /opt/timetv/backend/
/opt/timetv/venv/bin/pip install --upgrade /opt/timetv/backend
chown -R timetv:timetv /opt/timetv /var/lib/timetv
cd /opt/timetv/backend
set -a; source "$ENV_FILE"; set +a
/opt/timetv/venv/bin/python -m alembic upgrade head
/opt/timetv/venv/bin/python -m app.seed
systemctl restart timetv-backend
for i in {1..30}; do
  if curl -fsS http://127.0.0.1:8000/ready >/dev/null; then break; fi
  [[ "$i" == 30 ]] && { journalctl -u timetv-backend -n 100 --no-pager; exit 1; }
  sleep 1
done
PYTHONPATH=/opt/timetv/backend /opt/timetv/venv/bin/python "$ROOT_DIR/scripts/check_tmdb_live.py" Interstellar
if [[ "${PREWARM_POSTERS:-1}" == "1" ]]; then
  PYTHONPATH=/opt/timetv/backend /opt/timetv/venv/bin/python "$ROOT_DIR/scripts/prewarm_posters.py" --limit "${PREWARM_POSTER_LIMIT:-30}" || true
fi
echo 'Native CineTrack backend updated successfully.'
