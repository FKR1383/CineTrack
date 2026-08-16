#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="$ROOT_DIR/mobile"
JAR="$MOBILE_DIR/android/gradle/wrapper/gradle-wrapper.jar"

if [[ -f "$JAR" ]]; then
  exit 0
fi
command -v flutter >/dev/null || { echo "Flutter SDK is required to generate the Gradle wrapper." >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
flutter create \
  --platforms=android \
  --project-name=timetv_wrapper \
  --org=com.timetv \
  "$TMP_DIR/timetv_wrapper" >/dev/null

SOURCE="$TMP_DIR/timetv_wrapper/android/gradle/wrapper/gradle-wrapper.jar"
[[ -f "$SOURCE" ]] || { echo "Flutter did not generate gradle-wrapper.jar" >&2; exit 1; }
mkdir -p "$(dirname "$JAR")"
cp "$SOURCE" "$JAR"
echo "Generated mobile/android/gradle/wrapper/gradle-wrapper.jar without overwriting native project files."
