#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_IP="${SERVER_IP:-31.57.118.82}"
CA_FILE="${CA_FILE:-$ROOT_DIR/deploy/tls/ca.crt}"
CURL=(curl --fail --silent --show-error --cacert "$CA_FILE")

"${CURL[@]}" "https://$SERVER_IP/health" | grep -q '"status":"ok"'
"${CURL[@]}" "https://$SERVER_IP/ready" | grep -q '"status":"ready"'
"${CURL[@]}" "https://$SERVER_IP/api/v1/media/home" | grep -q 'popular_movies'
"${CURL[@]}" "https://$SERVER_IP/openapi.json" | grep -q 'CineTrack Advanced API'
echo "Smoke tests passed for https://$SERVER_IP"
