#!/usr/bin/env bash
# Signed release APK (and optionally an AAB) for the MonoKek POS app.
#
#   tool/build_release.sh [apk|aab]
#
# Environment:
#   API_URL             default server baked into the build (optional; the terminal can also be
#                       pointed at a server from its setup screen)
#   BUILD_NAME          versionName override, e.g. 1.2.3 (default: version from pubspec.yaml)
#   BUILD_NUMBER        versionCode override (default: build number from pubspec.yaml)
#   POS_CLIENT_SECRET   OAuth client secret of "monokek-pos". If unset, read from
#                       ../monokek-deploy/.env (IDENTITY_POS_CLIENT_SECRET).
#
# Requires android/key.properties (see android/key.properties.example).
set -euo pipefail
cd "$(dirname "$0")/.."

target="${1:-apk}"
env_file="../monokek-deploy/.env"

if [[ -z "${POS_CLIENT_SECRET:-}" && -f "$env_file" ]]; then
  POS_CLIENT_SECRET="$(grep -E '^IDENTITY_POS_CLIENT_SECRET=' "$env_file" | cut -d= -f2-)"
fi
if [[ -z "${POS_CLIENT_SECRET:-}" ]]; then
  echo "POS_CLIENT_SECRET is not set (and not found in $env_file): token refresh would fail." >&2
  exit 1
fi
if [[ ! -f android/key.properties ]]; then
  echo "android/key.properties is missing: copy android/key.properties.example and fill it in." >&2
  exit 1
fi

defines=(--dart-define=POS_CLIENT_SECRET="$POS_CLIENT_SECRET")
[[ -n "${API_URL:-}" ]] && defines+=(--dart-define=API_URL="$API_URL")
[[ -n "${BUILD_NAME:-}" ]] && defines+=(--build-name="$BUILD_NAME")
[[ -n "${BUILD_NUMBER:-}" ]] && defines+=(--build-number="$BUILD_NUMBER")

case "$target" in
  apk) flutter build apk --release "${defines[@]}"; out=build/app/outputs/flutter-apk/app-release.apk ;;
  aab) flutter build appbundle --release "${defines[@]}"; out=build/app/outputs/bundle/release/app-release.aab ;;
  *) echo "usage: $0 [apk|aab]" >&2; exit 2 ;;
esac

echo "Built: $out"
