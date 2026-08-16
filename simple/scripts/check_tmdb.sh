#!/usr/bin/env bash
set -euo pipefail

: "${TMDB_READ_ACCESS_TOKEN:?Set TMDB_READ_ACCESS_TOKEN to your TMDB API Read Access Token}"

query="${1:-Interstellar}"
encoded_query="$(python3 - <<'PY' "$query"
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1]))
PY
)"

curl --fail --silent --show-error \
  --header "Authorization: Bearer $TMDB_READ_ACCESS_TOKEN" \
  --header 'Accept: application/json' \
  "https://api.themoviedb.org/3/search/movie?query=${encoded_query}&include_adult=false&language=en-US&page=1" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("TMDB OK — results:", len(d.get("results", []))); [print(f"{x.get(chr(116)+chr(105)+chr(116)+chr(108)+chr(101), chr(63))} ({(x.get(chr(114)+chr(101)+chr(108)+chr(101)+chr(97)+chr(115)+chr(101)+chr(95)+chr(100)+chr(97)+chr(116)+chr(101)) or chr(45))[:4]})") for x in d.get("results", [])[:5]]'
