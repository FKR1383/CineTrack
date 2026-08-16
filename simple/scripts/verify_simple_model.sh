#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -d "$ROOT_DIR/backend" ]]; then
  echo "ERROR: backend directory exists in simple model" >&2
  exit 1
fi
if find "$ROOT_DIR/mobile" -type f \( -name '*.kt' -o -name '*.kts' -o -name '*.java' \) \
  ! -path '*/io/flutter/plugins/GeneratedPluginRegistrant.java' | grep -q .; then
  echo "ERROR: unexpected custom Kotlin/Java source found" >&2
  exit 1
fi
if grep -R -n -E 'API_BASE_URL|CERT_SHA256|31\.57\.118\.82|FastAPI|JWT' "$ROOT_DIR/mobile/lib"; then
  echo "ERROR: advanced/server coupling found in mobile source" >&2
  exit 1
fi
if ! grep -R -q 'api.themoviedb.org' "$ROOT_DIR/mobile/lib/core"; then
  echo "ERROR: direct TMDB client not found" >&2
  exit 1
fi
if ! grep -R -q 'cinetrack_simple.db' "$ROOT_DIR/mobile/lib/core/storage"; then
  echo "ERROR: local SQLite database not found" >&2
  exit 1
fi

echo "Simple-model architecture verified: Flutter -> TMDB, local SQLite, no backend."
