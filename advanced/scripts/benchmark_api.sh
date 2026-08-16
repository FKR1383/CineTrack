#!/usr/bin/env bash
set -euo pipefail
BASE_URL="${BASE_URL:-https://31.57.118.82}"
CA_CERT="${CA_CERT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/deploy/tls/ca.crt}"
REPEATS="${REPEATS:-5}"

curl_args=(-sS -o /dev/null)
if [[ "$BASE_URL" == https://* && -f "$CA_CERT" ]]; then
  curl_args+=(--cacert "$CA_CERT")
fi

printf 'Benchmarking %s (%s runs)\n' "$BASE_URL" "$REPEATS"
for endpoint in /ready /api/v1/media/home '/api/v1/media/search?q=Interstellar&page=1&page_size=10'; do
  echo "== $endpoint =="
  for ((i=1; i<=REPEATS; i++)); do
    curl "${curl_args[@]}" \
      -w 'http=%{http_code} connect=%{time_connect}s ttfb=%{time_starttransfer}s total=%{time_total}s\n' \
      "$BASE_URL$endpoint"
  done
done
