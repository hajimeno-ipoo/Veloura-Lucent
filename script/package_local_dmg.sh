#!/usr/bin/env bash
set -euo pipefail

DISPLAY_NAME="Veloura Lucent"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
DMG_PATH="$DIST_DIR/Veloura Lucent Local.dmg"
DMG_BACKGROUND="$ROOT_DIR/Resources/DmgInstaller/background.png"
DMG_BACKGROUND_NAME="Veloura Lucent Background.tiff"
CREATE_DMG_EXPECTED_VERSION="1.3.0"
DMG_WORK_DIR=""
DMG_STAGING_DIR=""
BASE_DMG_PATH=""
READ_WRITE_DMG_PATH=""
MOUNT_POINT=""
DMG_MOUNTED="false"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local status="$?"

  trap - EXIT
  if [[ "$DMG_MOUNTED" == "true" && -n "$MOUNT_POINT" ]]; then
    /usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    /bin/rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  if [[ -n "$DMG_WORK_DIR" && -d "$DMG_WORK_DIR" ]]; then
    /bin/rm -rf "$DMG_WORK_DIR"
  fi
  exit "$status"
}

trap cleanup EXIT

case "${1:-}" in
  "")
    ;;
  --help|-h)
    printf 'usage: %s\n' "$0"
    exit 0
    ;;
  *)
    printf 'usage: %s\n' "$0" >&2
    exit 2
    ;;
esac

for command in \
  /usr/bin/hdiutil \
  /usr/bin/codesign \
  /usr/bin/ditto \
  /usr/bin/mktemp \
  /usr/bin/osascript \
  /usr/bin/SetFile \
  /usr/bin/GetFileInfo \
  /usr/bin/sips; do
  [[ -x "$command" ]] || die "required macOS command is missing: $command"
done

CREATE_DMG_BIN="$(command -v create-dmg || true)"
[[ -n "$CREATE_DMG_BIN" && -x "$CREATE_DMG_BIN" ]] ||
  die "create-dmg $CREATE_DMG_EXPECTED_VERSION is required; install it with: brew install create-dmg"
[[ "$($CREATE_DMG_BIN --version)" == "create-dmg $CREATE_DMG_EXPECTED_VERSION" ]] ||
  die "create-dmg $CREATE_DMG_EXPECTED_VERSION is required"
[[ -f "$DMG_BACKGROUND" ]] || die "DMG background image is missing: $DMG_BACKGROUND"

/bin/mkdir -p "$DIST_DIR"

printf 'building the local-install app bundle...\n'
"$ROOT_DIR/script/build_and_run.sh" --package

[[ -d "$APP_BUNDLE" ]] || die "published app bundle is missing: $APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

DMG_WORK_DIR="$(/usr/bin/mktemp -d "$DIST_DIR/.veloura-lucent-dmg.XXXXXX")"
DMG_STAGING_DIR="$DMG_WORK_DIR/staging"
BASE_DMG_PATH="$DMG_WORK_DIR/Veloura Lucent Base.dmg"
READ_WRITE_DMG_PATH="$DMG_WORK_DIR/Veloura Lucent ReadWrite.dmg"
/bin/mkdir -p "$DMG_STAGING_DIR"
/usr/bin/ditto "$APP_BUNDLE" "$DMG_STAGING_DIR/$DISPLAY_NAME.app"

[[ ! -L "$DMG_PATH" ]] || die "DMG output path must not be a symbolic link: $DMG_PATH"
if [[ -e "$DMG_PATH" && ! -f "$DMG_PATH" ]]; then
  die "DMG output path is not a regular file: $DMG_PATH"
fi

printf 'creating local-install DMG...\n'
"$CREATE_DMG_BIN" \
  --volname "$DISPLAY_NAME" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --text-size 14 \
  --icon-size 128 \
  --icon "$DISPLAY_NAME.app" 200 200 \
  --app-drop-link 600 200 \
  --format UDZO \
  --filesystem HFS+ \
  --overwrite \
  "$BASE_DMG_PATH" \
  "$DMG_STAGING_DIR"

/usr/bin/hdiutil convert "$BASE_DMG_PATH" \
  -format UDRW \
  -ov \
  -o "$READ_WRITE_DMG_PATH" >/dev/null

MOUNT_POINT="$(/usr/bin/mktemp -d /tmp/veloura-lucent-dmg-mount.XXXXXX)"
/usr/bin/hdiutil attach "$READ_WRITE_DMG_PATH" \
  -readwrite \
  -mountpoint "$MOUNT_POINT" >/dev/null
DMG_MOUNTED="true"

[[ -d "$MOUNT_POINT/$DISPLAY_NAME.app" ]] || die "DMG does not contain the app bundle"
[[ -L "$MOUNT_POINT/Applications" ]] || die "DMG does not contain the Applications link"
[[ "$(/usr/bin/readlink "$MOUNT_POINT/Applications")" == "/Applications" ]] ||
  die "DMG Applications link does not target /Applications"

printf 'applying Finder layout for macOS 26 compatibility...\n'
/usr/bin/sips -s format tiff "$DMG_BACKGROUND" \
  --out "$MOUNT_POINT/$DMG_BACKGROUND_NAME" >/dev/null

FINDER_DISK_NAME="${MOUNT_POINT##*/}"
/usr/bin/osascript \
  -e 'tell application "Finder"' \
  -e "tell disk \"$FINDER_DISK_NAME\"" \
  -e 'open' \
  -e 'set current view of container window to icon view' \
  -e 'set toolbar visible of container window to false' \
  -e 'set statusbar visible of container window to false' \
  -e 'set pathbar visible of container window to false' \
  -e 'set bounds of container window to {200, 120, 1000, 520}' \
  -e 'set viewOptions to the icon view options of container window' \
  -e 'set arrangement of viewOptions to not arranged' \
  -e 'set icon size of viewOptions to 128' \
  -e 'set text size of viewOptions to 14' \
  -e "set background picture of viewOptions to file \"$DMG_BACKGROUND_NAME\"" \
  -e "set position of item \"$DISPLAY_NAME.app\" of container window to {200, 200}" \
  -e 'set position of item "Applications" of container window to {600, 200}' \
  -e 'update without registering applications' \
  -e 'delay 2' \
  -e 'close container window' \
  -e 'end tell' \
  -e 'end tell'

/usr/bin/SetFile -a V "$MOUNT_POINT/$DMG_BACKGROUND_NAME"

FINDER_ICON_SIZE="$(/usr/bin/osascript \
  -e 'tell application "Finder"' \
  -e "tell disk \"$FINDER_DISK_NAME\"" \
  -e 'open' \
  -e 'set viewOptions to the icon view options of container window' \
  -e 'set savedIconSize to icon size of viewOptions' \
  -e 'delay 3' \
  -e 'close container window' \
  -e 'return savedIconSize' \
  -e 'end tell' \
  -e 'end tell')"

[[ "$FINDER_ICON_SIZE" == "128" ]] ||
  die "Finder icon size was not saved: $FINDER_ICON_SIZE"
[[ "$(/usr/bin/GetFileInfo -a "$MOUNT_POINT/$DMG_BACKGROUND_NAME")" == *V* ]] ||
  die "DMG background file is not hidden"
[[ -f "$MOUNT_POINT/.DS_Store" ]] || die "Finder layout metadata is missing"
/usr/bin/grep -aFq "$DMG_BACKGROUND_NAME" "$MOUNT_POINT/.DS_Store" ||
  die "Finder background reference was not saved"

/bin/sync
/usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null
DMG_MOUNTED="false"
/bin/rmdir "$MOUNT_POINT"
MOUNT_POINT=""

/usr/bin/hdiutil convert "$READ_WRITE_DMG_PATH" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$DMG_PATH" >/dev/null

/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null

MOUNT_POINT="$(/usr/bin/mktemp -d /tmp/veloura-lucent-dmg-verify.XXXXXX)"
/usr/bin/hdiutil attach "$DMG_PATH" \
  -nobrowse \
  -readonly \
  -mountpoint "$MOUNT_POINT" >/dev/null
DMG_MOUNTED="true"

[[ -d "$MOUNT_POINT/$DISPLAY_NAME.app" ]] || die "final DMG does not contain the app bundle"
[[ -L "$MOUNT_POINT/Applications" ]] || die "final DMG does not contain the Applications link"
[[ "$(/usr/bin/readlink "$MOUNT_POINT/Applications")" == "/Applications" ]] ||
  die "final DMG Applications link does not target /Applications"
[[ -f "$MOUNT_POINT/$DMG_BACKGROUND_NAME" ]] || die "final DMG background is missing"
[[ "$(/usr/bin/GetFileInfo -a "$MOUNT_POINT/$DMG_BACKGROUND_NAME")" == *V* ]] ||
  die "final DMG background file is not hidden"
/usr/bin/grep -aFq "$DMG_BACKGROUND_NAME" "$MOUNT_POINT/.DS_Store" ||
  die "final DMG background reference is missing"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$MOUNT_POINT/$DISPLAY_NAME.app"

/usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null
DMG_MOUNTED="false"
/bin/rmdir "$MOUNT_POINT"
MOUNT_POINT=""

printf 'created local-install DMG: %s\n' "$DMG_PATH"
