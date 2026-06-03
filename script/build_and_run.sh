#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
BUILD_PRODUCT_NAME="VelouraLucent"
DISPLAY_NAME="Veloura Lucent"
BUNDLE_ID="com.codex.VelouraLucent"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
LEGACY_APP_BUNDLE="$DIST_DIR/SpectralLifter.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$BUILD_PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon-1024.png"
RUNTIME_ICON_NAME="AppIcon-1024.png"
ICON_CATALOG="$DIST_DIR/Assets.xcassets"
APP_ICON_SET="$ICON_CATALOG/AppIcon.appiconset"
ASSETCATALOG_INFO="$DIST_DIR/assetcatalog_generated_info.plist"

render_icon() {
  local size="$1"
  local output_name="$2"
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$3/$output_name" >/dev/null
}

write_asset_catalog_metadata() {
  cat >"$ICON_CATALOG/Contents.json" <<'JSON'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

  cat >"$APP_ICON_SET/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
}

generate_app_icon_assets() {
  [[ -f "$ICON_SOURCE" ]] || return

  rm -rf "$ICON_CATALOG" "$ASSETCATALOG_INFO"
  mkdir -p "$APP_RESOURCES" "$APP_ICON_SET"
  write_asset_catalog_metadata

  render_icon 16 icon_16x16.png "$APP_ICON_SET"
  render_icon 32 icon_16x16@2x.png "$APP_ICON_SET"
  render_icon 32 icon_32x32.png "$APP_ICON_SET"
  render_icon 64 icon_32x32@2x.png "$APP_ICON_SET"
  render_icon 128 icon_128x128.png "$APP_ICON_SET"
  render_icon 256 icon_128x128@2x.png "$APP_ICON_SET"
  render_icon 256 icon_256x256.png "$APP_ICON_SET"
  render_icon 512 icon_256x256@2x.png "$APP_ICON_SET"
  render_icon 512 icon_512x512.png "$APP_ICON_SET"
  cp "$ICON_SOURCE" "$APP_ICON_SET/icon_512x512@2x.png"

  xcrun actool \
    --compile "$APP_RESOURCES" \
    --platform macosx \
    --target-device mac \
    --minimum-deployment-target "$MIN_SYSTEM_VERSION" \
    --app-icon AppIcon \
    --output-partial-info-plist "$ASSETCATALOG_INFO" \
    "$ICON_CATALOG" >/dev/null
}

pkill -x "$BUILD_PRODUCT_NAME" >/dev/null 2>&1 || true

swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$BUILD_PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
if [[ "$LEGACY_APP_BUNDLE" != "$APP_BUNDLE" ]]; then
  rm -rf "$LEGACY_APP_BUNDLE"
fi
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
generate_app_icon_assets
if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$APP_RESOURCES/$RUNTIME_ICON_NAME"
fi

ICON_PLIST_BLOCK=""
if [[ -f "$ICON_SOURCE" ]]; then
  ICON_PLIST_BLOCK=$'  <key>CFBundleIconFile</key>\n  <string>AppIcon</string>\n  <key>CFBundleIconName</key>\n  <string>AppIcon</string>'
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$BUILD_PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
${ICON_PLIST_BLOCK}
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$BUILD_PRODUCT_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$BUILD_PRODUCT_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
