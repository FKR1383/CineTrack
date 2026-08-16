#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:-/etc/timetv/timetv.env}"
if [[ ! -f "$TARGET" ]]; then
  echo "Environment file not found: $TARGET" >&2
  exit 1
fi
read -rsp 'TMDB API Read Access Token (input hidden): ' TOKEN
echo
if [[ -z "$TOKEN" ]]; then
  echo 'Token cannot be empty.' >&2
  exit 1
fi
read -rsp 'TMDB API Key (optional; press Enter to skip): ' API_KEY
echo
export TOKEN API_KEY TARGET
python3 - <<'PY'
from pathlib import Path
import os
p=Path(os.environ['TARGET'])
lines=p.read_text().splitlines()
values={
    'MEDIA_PROVIDER':'tmdb',
    'TMDB_READ_ACCESS_TOKEN':os.environ['TOKEN'],
    'TMDB_API_KEY':os.environ.get('API_KEY',''),
    'TMDB_SEARCH_LIVE':'true',
}
seen=set(); out=[]
for line in lines:
    key=line.split('=',1)[0].strip() if '=' in line and not line.lstrip().startswith('#') else None
    if key in values:
        out.append(f"{key}={values[key]}"); seen.add(key)
    else:
        out.append(line)
for key,value in values.items():
    if key not in seen: out.append(f"{key}={value}")
p.write_text('\n'.join(out)+'\n')
PY
chmod 640 "$TARGET" 2>/dev/null || true
echo "TMDB credentials saved to $TARGET (not printed)."
