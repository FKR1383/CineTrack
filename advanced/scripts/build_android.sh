#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="$ROOT_DIR/mobile"
SERVER_IP="${SERVER_IP:-31.57.118.82}"
API_BASE_URL="${API_BASE_URL:-https://$SERVER_IP/api/v1}"
PIN_FILE="${PIN_FILE:-$ROOT_DIR/deploy/tls/fingerprint.sha256}"

command -v flutter >/dev/null || { echo "Flutter SDK is required." >&2; exit 1; }
"$ROOT_DIR/scripts/verify_flutter_frontend.sh"
[[ -f "$PIN_FILE" ]] || { echo "Certificate fingerprint missing; run scripts/generate_tls.sh first." >&2; exit 1; }
CERT_SHA256="${CERT_SHA256:-$(tr -d '[:space:]' < "$PIN_FILE")}"
[[ "$CERT_SHA256" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "Invalid SHA-256 pin." >&2; exit 1; }

"$ROOT_DIR/scripts/ensure_gradle_wrapper.sh"
cd "$MOBILE_DIR"
if [[ ! -f android/key.properties && "${ALLOW_DEBUG_SIGNING:-0}" != "1" ]]; then
  echo "Release signing is not configured. Run scripts/generate_android_keystore.sh or set ALLOW_DEBUG_SIGNING=1 for a non-production build." >&2
  exit 1
fi

flutter pub get
flutter analyze
flutter test
flutter build apk --release \
  --dart-define="API_BASE_URL=$API_BASE_URL" \
  --dart-define="CERT_SHA256=$CERT_SHA256"
flutter build appbundle --release \
  --dart-define="API_BASE_URL=$API_BASE_URL" \
  --dart-define="CERT_SHA256=$CERT_SHA256"

mkdir -p "$ROOT_DIR/releases"
cp build/app/outputs/flutter-apk/app-release.apk "$ROOT_DIR/releases/CineTrack-Advanced.apk"
cp build/app/outputs/bundle/release/app-release.aab "$ROOT_DIR/releases/CineTrack-Advanced.aab"
sha256sum "$ROOT_DIR/releases/CineTrack-Advanced.apk" "$ROOT_DIR/releases/CineTrack-Advanced.aab" \
  > "$ROOT_DIR/releases/SHA256SUMS"
echo "Release artifacts are in $ROOT_DIR/releases"
