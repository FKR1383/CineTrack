#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/docs/screenshots}"
NAME="${1:-screen-$(date +%Y%m%d-%H%M%S)}"
DURATION="${DURATION:-60}"
mkdir -p "$OUT_DIR"
command -v adb >/dev/null || { echo "adb is required." >&2; exit 1; }
adb get-state >/dev/null
adb exec-out screencap -p > "$OUT_DIR/$NAME.png"
adb shell screenrecord --time-limit "$DURATION" "/sdcard/$NAME.mp4"
adb pull "/sdcard/$NAME.mp4" "$OUT_DIR/$NAME.mp4" >/dev/null
adb shell rm "/sdcard/$NAME.mp4"
echo "Saved $OUT_DIR/$NAME.png and $OUT_DIR/$NAME.mp4"
