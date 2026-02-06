#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="${SCHEME:-Zoontag}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/.build/Zoontag.xcarchive}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/.build/release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/DerivedDataRelease}"
ZIP_NAME="${ZIP_NAME:-Zoontag-macOS.zip}"
APP_NAME="${APP_NAME:-Zoontag.app}"

mkdir -p "$OUTPUT_DIR"
rm -rf "$ARCHIVE_PATH"
rm -rf "$DERIVED_DATA_PATH"

xcodebuild archive \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app not found at $APP_PATH" >&2
  exit 1
fi

ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"
rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

echo "Created package:"
echo "  $ZIP_PATH"
echo "  $ZIP_PATH.sha256"
