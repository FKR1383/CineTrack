#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="$ROOT_DIR/mobile"

: "${TMDB_READ_ACCESS_TOKEN:?Set TMDB_READ_ACCESS_TOKEN to your TMDB API Read Access Token}"
TMDB_LANGUAGE="${TMDB_LANGUAGE:-en-US}"
TMDB_REGION="${TMDB_REGION:-US}"

cd "$MOBILE_DIR"
flutter pub get
exec flutter run "$@" \
  --dart-define="TMDB_READ_ACCESS_TOKEN=$TMDB_READ_ACCESS_TOKEN" \
  --dart-define="TMDB_LANGUAGE=$TMDB_LANGUAGE" \
  --dart-define="TMDB_REGION=$TMDB_REGION"
