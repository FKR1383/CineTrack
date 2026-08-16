#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="$ROOT_DIR/mobile"

[[ -f "$MOBILE_DIR/pubspec.yaml" ]] || { echo 'mobile/pubspec.yaml is missing.' >&2; exit 1; }
[[ -f "$MOBILE_DIR/lib/main.dart" ]] || { echo 'mobile/lib/main.dart is missing.' >&2; exit 1; }

mapfile -t native_sources < <(
  find "$MOBILE_DIR/android" \
    -path "$MOBILE_DIR/android/.gradle" -prune -o \
    -path "*/io/flutter/plugins/GeneratedPluginRegistrant.java" -prune -o \
    -type f \( -name '*.kt' -o -name '*.kts' -o -name '*.java' \) -print
)
if (( ${#native_sources[@]} > 0 )); then
  printf 'Unexpected native application source/build DSL files:\n%s\n' "${native_sources[*]}" >&2
  exit 1
fi

if grep -R --line-number --include='*.dart' 'MethodChannel' "$MOBILE_DIR/lib"; then
  echo 'Custom platform-channel application logic is not allowed in the Flutter-only frontend.' >&2
  exit 1
fi

dart_files=$(find "$MOBILE_DIR/lib" -type f -name '*.dart' | wc -l)
dart_lines=$(find "$MOBILE_DIR/lib" -type f -name '*.dart' -print0 | xargs -0 cat | wc -l)
printf 'Flutter/Dart frontend verified: %s Dart files, %s Dart lines, no Kotlin/Java source.\n' "$dart_files" "$dart_lines"
