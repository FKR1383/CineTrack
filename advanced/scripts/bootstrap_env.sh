#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT_DIR/.env"

if [[ -f "$TARGET" && "${FORCE:-0}" != "1" ]]; then
  echo ".env already exists; refusing to overwrite it."
  exit 0
fi

DB_PASSWORD="$(openssl rand -hex 24)"
JWT_SECRET="$(openssl rand -hex 48)"
ADMIN_PASSWORD="CineTrack-$(openssl rand -hex 12)-A1!"
SERVER_IP="${SERVER_IP:-31.57.118.82}"

cp "$ROOT_DIR/.env.example" "$TARGET"
python3 - "$TARGET" "$SERVER_IP" "$DB_PASSWORD" "$JWT_SECRET" "$ADMIN_PASSWORD" <<'PY'
from pathlib import Path
import sys
path=Path(sys.argv[1])
ip, db, jwt, admin=sys.argv[2:]
text=path.read_text()
text=text.replace('31.57.118.82', ip)
text=text.replace('CHANGE_ME_RANDOM_DATABASE_PASSWORD', db)
text=text.replace('CHANGE_ME_WITH_AT_LEAST_64_RANDOM_CHARACTERS', jwt)
text=text.replace('CHANGE_ME_STRONG_ADMIN_PASSWORD', admin)
path.write_text(text)
PY
chmod 600 "$TARGET"

echo "Created $TARGET with random database/JWT/admin secrets."
echo "Initial administrator: admin@cinetrack.example"
echo "Initial administrator password: $ADMIN_PASSWORD"
echo "Now edit $TARGET and set TMDB_READ_ACCESS_TOKEN (preferred) or TMDB_API_KEY."
