#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/mobile/android"
KEYSTORE="$ANDROID_DIR/app/timetv-release.jks"
STORE_PASSWORD="${ANDROID_STORE_PASSWORD:-$(openssl rand -hex 16)}"
KEY_PASSWORD="${ANDROID_KEY_PASSWORD:-$STORE_PASSWORD}"
ALIAS="${ANDROID_KEY_ALIAS:-timetv}"

command -v keytool >/dev/null || { echo "keytool is required (install a JDK)." >&2; exit 1; }
if [[ -e "$KEYSTORE" && "${FORCE:-0}" != "1" ]]; then
  echo "$KEYSTORE already exists; refusing to overwrite." >&2
  exit 1
fi

keytool -genkeypair -v -keystore "$KEYSTORE" -storetype JKS \
  -storepass "$STORE_PASSWORD" -keypass "$KEY_PASSWORD" -alias "$ALIAS" \
  -keyalg RSA -keysize 3072 -validity 10000 \
  -dname "CN=CineTrack, OU=Mobile, O=CineTrack Educational Project, L=Tehran, C=IR"

cat > "$ANDROID_DIR/key.properties" <<PROPS
storePassword=$STORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$ALIAS
storeFile=app/timetv-release.jks
PROPS
chmod 600 "$ANDROID_DIR/key.properties" "$KEYSTORE"

echo "Release keystore created. Back it up securely; losing it prevents future app updates."
echo "ANDROID_STORE_PASSWORD=$STORE_PASSWORD"
echo "ANDROID_KEY_PASSWORD=$KEY_PASSWORD"
echo "ANDROID_KEY_ALIAS=$ALIAS"
