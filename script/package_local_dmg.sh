#!/usr/bin/env bash
set -euo pipefail

DISPLAY_NAME="Veloura Lucent"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
DMG_PATH="$DIST_DIR/Veloura Lucent Local.dmg"
DMG_STAGING_DIR=""
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
  if [[ -n "$DMG_STAGING_DIR" && -d "$DMG_STAGING_DIR" ]]; then
    /bin/rm -rf "$DMG_STAGING_DIR"
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

for command in /usr/bin/hdiutil /usr/bin/codesign /usr/bin/ditto /usr/bin/mktemp; do
  [[ -x "$command" ]] || die "required macOS command is missing: $command"
done

/bin/mkdir -p "$DIST_DIR"

printf 'building the local-install app bundle...\n'
"$ROOT_DIR/script/build_and_run.sh" --package

[[ -d "$APP_BUNDLE" ]] || die "published app bundle is missing: $APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

DMG_STAGING_DIR="$(/usr/bin/mktemp -d "$DIST_DIR/.veloura-lucent-dmg.XXXXXX")"
/usr/bin/ditto "$APP_BUNDLE" "$DMG_STAGING_DIR/$DISPLAY_NAME.app"
/bin/ln -s /Applications "$DMG_STAGING_DIR/Applications"

[[ ! -L "$DMG_PATH" ]] || die "DMG output path must not be a symbolic link: $DMG_PATH"
if [[ -e "$DMG_PATH" && ! -f "$DMG_PATH" ]]; then
  die "DMG output path is not a regular file: $DMG_PATH"
fi

printf 'creating local-install DMG...\n'
/usr/bin/hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null

/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null

MOUNT_POINT="$(/usr/bin/mktemp -d /tmp/veloura-lucent-dmg-mount.XXXXXX)"
/usr/bin/hdiutil attach "$DMG_PATH" \
  -nobrowse \
  -readonly \
  -mountpoint "$MOUNT_POINT" >/dev/null
DMG_MOUNTED="true"

[[ -d "$MOUNT_POINT/$DISPLAY_NAME.app" ]] || die "DMG does not contain the app bundle"
[[ -L "$MOUNT_POINT/Applications" ]] || die "DMG does not contain the Applications link"
[[ "$(/usr/bin/readlink "$MOUNT_POINT/Applications")" == "/Applications" ]] ||
  die "DMG Applications link does not target /Applications"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$MOUNT_POINT/$DISPLAY_NAME.app"

/usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null
DMG_MOUNTED="false"
/bin/rmdir "$MOUNT_POINT"
MOUNT_POINT=""

printf 'created local-install DMG: %s\n' "$DMG_PATH"
