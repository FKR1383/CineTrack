# Native Ubuntu deployment (no Docker)

Recommended for the 1 GB VPS.

```text
Nginx -> Uvicorn/FastAPI -> PostgreSQL + Redis -> TMDB
```

## Existing native server update

Copy/extract the new project, then:

```bash
cd /root/CineTrack-TMDB-Advanced
sudo ./scripts/configure_tmdb.sh /etc/timetv/timetv.env
sudo ./scripts/update_native_backend.sh
```

The update script:

1. syncs backend source to `/opt/timetv/backend`;
2. installs/upgrades Python package dependencies;
3. runs Alembic migrations;
4. seeds/refreshes the TMDB home cache when possible;
5. restarts `timetv-backend`;
6. checks readiness;
7. executes a real `Interstellar` TMDB search.

## Fresh server

```bash
cd /root/CineTrack-TMDB-Advanced
SERVER_IP=31.57.118.82 ./scripts/bootstrap_env.sh
./scripts/configure_tmdb.sh .env
sudo SERVER_IP=31.57.118.82 ./scripts/deploy_native_ubuntu.sh
```

The deployment installs native PostgreSQL, Redis, Nginx and Python, creates the system user, database, virtualenv and systemd service, configures UFW, TLS and Nginx, runs migrations and checks TMDB.

## Service locations

```text
Backend source       /opt/timetv/backend
Python virtualenv    /opt/timetv/venv
Environment          /etc/timetv/timetv.env
Uploads/posters      /var/lib/timetv/uploads
Systemd              timetv-backend.service
Nginx site           /etc/nginx/sites-available/timetv
TLS                   /etc/nginx/tls/timetv
```

The historical `timetv` paths/service name are retained to update the already-deployed server without unnecessary migration risk; application branding is CineTrack.

## Health and logs

```bash
systemctl is-active timetv-backend nginx postgresql redis-server
curl http://127.0.0.1:8000/ready
journalctl -u timetv-backend -f
tail -f /var/log/nginx/access.log /var/log/nginx/error.log
```

Public HTTPS test using the project CA:

```bash
curl --cacert deploy/tls/ca.crt https://31.57.118.82/ready
```
