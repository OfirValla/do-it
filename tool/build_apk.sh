#!/usr/bin/env bash
# Builds the Do It Android APK and copies it to dist/ with a versioned name.
#
# Usage: tool/build_apk.sh [--debug|--profile|--release] [--split-per-abi]
#                          [--skip-tests] [--skip-codegen] [--out DIR]
set -euo pipefail

MODE="release"
SPLIT=""
SKIP_TESTS=0
SKIP_CODEGEN=0
OUT_DIR="dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug|--profile|--release) MODE="${1#--}" ;;
    --split-per-abi) SPLIT="--split-per-abi" ;;
    --skip-tests) SKIP_TESTS=1 ;;
    --skip-codegen) SKIP_CODEGEN=1 ;;
    --out) OUT_DIR="$2"; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

step() { printf '\n==> %s\n' "$1"; }

command -v flutter >/dev/null || { echo "flutter not found on PATH" >&2; exit 1; }

VERSION="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -1 | tr -d '[:space:]')"
echo "Do It $VERSION - $MODE build"

step "flutter pub get";        flutter pub get
if [[ $SKIP_CODEGEN -eq 0 ]]; then
  step "Drift code generation"; dart run build_runner build
fi
step "flutter analyze";        flutter analyze
if [[ $SKIP_TESTS -eq 0 ]]; then
  step "flutter test";         flutter test
fi
step "flutter build apk --$MODE $SPLIT"; flutter build apk "--$MODE" $SPLIT

mkdir -p "$OUT_DIR"
step "Output"
shopt -s nullglob
for apk in build/app/outputs/flutter-apk/*-"$MODE".apk; do
  base="$(basename "$apk" .apk)"
  variant="${base#app-}"
  dest="$OUT_DIR/do_it-$VERSION-$variant.apk"
  cp -f "$apk" "$dest"
  if command -v sha256sum >/dev/null; then hash="$(sha256sum "$dest" | cut -d' ' -f1)"; else hash="$(shasum -a 256 "$dest" | cut -d' ' -f1)"; fi
  size_mb="$(du -m "$dest" | cut -f1)"
  echo "$dest  (${size_mb} MB)"
  echo "  sha256 $hash"
done

echo
echo "Install with: adb install -r <apk>"
