#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_IP="${SERVER_IP:-31.57.118.82}"

if [[ "$EUID" -ne 0 ]]; then
  exec sudo --preserve-env=SERVER_IP bash "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv python3-pip postgresql postgresql-contrib redis-server nginx rsync curl openssl xxd ufw

cd "$ROOT_DIR"
[[ -f .env ]] || SERVER_IP="$SERVER_IP" "$ROOT_DIR/scripts/bootstrap_env.sh"
[[ -f deploy/tls/server.crt && -f deploy/tls/server.key && -f deploy/tls/ca.crt ]] || SERVER_IP="$SERVER_IP" "$ROOT_DIR/scripts/generate_tls.sh"

if ! grep -Eq '^MEDIA_PROVIDER=tmdb([[:space:]]|$)' .env; then
  echo 'ERROR: set MEDIA_PROVIDER=tmdb in .env.' >&2; exit 1
fi
TOKEN="$(grep '^TMDB_READ_ACCESS_TOKEN=' .env | head -1 | cut -d= -f2- || true)"
API_KEY="$(grep '^TMDB_API_KEY=' .env | head -1 | cut -d= -f2- || true)"
if [[ -z "$TOKEN" && -z "$API_KEY" ]]; then
  echo 'ERROR: configure TMDB_READ_ACCESS_TOKEN (preferred) or TMDB_API_KEY in .env first.' >&2
  exit 1
fi

ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
systemctl enable --now postgresql redis-server

DB_NAME="$(grep '^POSTGRES_DB=' .env | cut -d= -f2-)"
DB_USER="$(grep '^POSTGRES_USER=' .env | cut -d= -f2-)"
DB_PASS="$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)"
export DB_NAME DB_USER DB_PASS
python3 - <<'PY' >/tmp/cinetrack-db-bootstrap.sql
import os
u=os.environ['DB_USER'].replace('"','""')
p=os.environ['DB_PASS'].replace("'","''")
print(f"SELECT 'CREATE ROLE \"{u}\" LOGIN PASSWORD ''{p}''' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='{u}')\\gexec")
print(f"ALTER ROLE \"{u}\" WITH LOGIN PASSWORD '{p}';")
PY
sudo -u postgres psql -v ON_ERROR_STOP=1 -f /tmp/cinetrack-db-bootstrap.sql
rm -f /tmp/cinetrack-db-bootstrap.sql
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 || sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"

id timetv >/dev/null 2>&1 || useradd --system --create-home --home-dir /opt/timetv --shell /usr/sbin/nologin timetv
mkdir -p /opt/timetv/backend /etc/timetv /var/lib/timetv/uploads
rsync -a --delete --exclude '.env' --exclude '__pycache__' "$ROOT_DIR/backend/" /opt/timetv/backend/
python3 -m venv /opt/timetv/venv
/opt/timetv/venv/bin/pip install --upgrade pip
/opt/timetv/venv/bin/pip install /opt/timetv/backend

cp .env /etc/timetv/timetv.env
sed -i 's/@postgres:5432/@127.0.0.1:5432/g; s#redis://redis:6379#redis://127.0.0.1:6379#g; s#^UPLOAD_DIR=.*#UPLOAD_DIR=/var/lib/timetv/uploads#' /etc/timetv/timetv.env
chown root:timetv /etc/timetv/timetv.env
chmod 640 /etc/timetv/timetv.env
chown -R timetv:timetv /opt/timetv /var/lib/timetv

cat >/etc/systemd/system/timetv-backend.service <<'UNIT'
[Unit]
Description=CineTrack Advanced FastAPI Backend
After=network-online.target postgresql.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=timetv
Group=timetv
WorkingDirectory=/opt/timetv/backend
EnvironmentFile=/etc/timetv/timetv.env
Environment=PYTHONUNBUFFERED=1
ExecStartPre=/opt/timetv/venv/bin/python -m alembic upgrade head
ExecStart=/opt/timetv/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 1 --proxy-headers --forwarded-allow-ips=127.0.0.1
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

mkdir -p /etc/nginx/tls/timetv
cp deploy/tls/server.crt /etc/nginx/tls/timetv/server.crt
cp deploy/tls/server.key /etc/nginx/tls/timetv/server.key
cp deploy/tls/ca.crt /etc/nginx/tls/timetv/ca.crt
chmod 600 /etc/nginx/tls/timetv/server.key
chmod 644 /etc/nginx/tls/timetv/server.crt /etc/nginx/tls/timetv/ca.crt

cat >/etc/nginx/sites-available/timetv <<NGINX
limit_req_zone \$binary_remote_addr zone=cinetrack_api:10m rate=20r/s;
upstream cinetrack_backend { server 127.0.0.1:8000; keepalive 16; }
server { listen 80; listen [::]:80; server_name $SERVER_IP; return 301 https://\$host\$request_uri; }
server {
  listen 443 ssl; listen [::]:443 ssl; server_name $SERVER_IP;
  ssl_certificate /etc/nginx/tls/timetv/server.crt;
  ssl_certificate_key /etc/nginx/tls/timetv/server.key;
  ssl_protocols TLSv1.2 TLSv1.3; ssl_session_cache shared:SSL:10m;
  client_max_body_size 6m;
  gzip on; gzip_vary on; gzip_min_length 1024; gzip_types application/json text/plain text/css application/javascript image/svg+xml;
  location = /health { proxy_pass http://cinetrack_backend/health; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto https; }
  location = /ready { proxy_pass http://cinetrack_backend/ready; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto https; }
  location /api/ {
    limit_req zone=cinetrack_api burst=40 nodelay;
    proxy_pass http://cinetrack_backend; proxy_http_version 1.1; proxy_set_header Connection "";
    proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https;
    proxy_connect_timeout 5s; proxy_read_timeout 60s; proxy_send_timeout 60s;
  }
  location /uploads/ { alias /var/lib/timetv/uploads/; expires 30d; add_header Cache-Control "public, max-age=2592000, immutable"; access_log off; }
  location = /openapi.json { proxy_pass http://cinetrack_backend/openapi.json; }
  location /docs { proxy_pass http://cinetrack_backend/docs; }
  location /redoc { proxy_pass http://cinetrack_backend/redoc; }
  location / { default_type text/plain; return 200 "CineTrack Advanced API\n"; }
}
NGINX
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/timetv /etc/nginx/sites-enabled/timetv
nginx -t
systemctl daemon-reload
systemctl enable --now timetv-backend nginx
systemctl restart timetv-backend nginx

cd /opt/timetv/backend
set -a; source /etc/timetv/timetv.env; set +a
/opt/timetv/venv/bin/python -m app.seed
for i in {1..30}; do
  if curl --silent --fail --cacert "$ROOT_DIR/deploy/tls/ca.crt" "https://$SERVER_IP/ready" >/dev/null; then break; fi
  [[ "$i" == 30 ]] && { journalctl -u timetv-backend -n 100 --no-pager; exit 1; }
  sleep 2
done
PYTHONPATH=/opt/timetv/backend /opt/timetv/venv/bin/python "$ROOT_DIR/scripts/check_tmdb_live.py" Interstellar
if [[ "${PREWARM_POSTERS:-1}" == "1" ]]; then
  PYTHONPATH=/opt/timetv/backend /opt/timetv/venv/bin/python "$ROOT_DIR/scripts/prewarm_posters.py" --limit "${PREWARM_POSTER_LIMIT:-30}" || true
fi

echo "CineTrack native stack is ready at https://$SERVER_IP"
echo "Swagger: https://$SERVER_IP/docs"
echo "Mobile certificate pin: $(cat "$ROOT_DIR/deploy/tls/fingerprint.sha256")"
