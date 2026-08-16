#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="$ROOT_DIR/mobile"
SERVER_IP="${SERVER_IP:-31.57.118.82}"
API_BASE_URL="${API_BASE_URL:-https://$SERVER_IP/api/v1}"
PIN_FILE="${PIN_FILE:-$ROOT_DIR/deploy/tls/fingerprint.sha256}"

command -v flutter >/dev/null || { echo 'Flutter SDK is required.' >&2; exit 1; }
"$ROOT_DIR/scripts/verify_flutter_frontend.sh"

DART_DEFINES=("--dart-define=API_BASE_URL=$API_BASE_URL")
if [[ -f "$PIN_FILE" ]]; then
  CERT_SHA256="${CERT_SHA256:-$(tr -d '[:space:]' < "$PIN_FILE")}" 
  [[ "$CERT_SHA256" =~ ^[0-9a-fA-F]{64}$ ]] || { echo 'Invalid certificate SHA-256 pin.' >&2; exit 1; }
  DART_DEFINES+=("--dart-define=CERT_SHA256=$CERT_SHA256")
elif [[ "${ALLOW_UNPINNED_DEV:-0}" == "1" ]]; then
  DART_DEFINES+=("--dart-define=ALLOW_UNPINNED_DEV=true")
else
  echo "Certificate pin file not found: $PIN_FILE" >&2
  echo 'Generate server TLS first or set ALLOW_UNPINNED_DEV=1 only for local development.' >&2
  exit 1
fi

cd "$MOBILE_DIR"
flutter pub get
exec flutter run "${DART_DEFINES[@]}" "$@"
