#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
BUILD_PRODUCT_NAME="VelouraLucent"
DISPLAY_NAME="Veloura Lucent"
BUNDLE_ID="com.codex.VelouraLucent"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
FINAL_APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
FINAL_APP_BINARY="$FINAL_APP_BUNDLE/Contents/MacOS/$BUILD_PRODUCT_NAME"
LEGACY_APP_BUNDLE="$DIST_DIR/SpectralLifter.app"
APP_LOCALIZATION_SOURCE="$ROOT_DIR/Resources/ja.lproj"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon-1024.png"
RUNTIME_ICON_NAME="AppIcon-1024.png"
RESOURCE_BUNDLE_NAME="${BUILD_PRODUCT_NAME}_${BUILD_PRODUCT_NAME}.bundle"

STAGING_DIR=""
APP_BUNDLE=""
APP_CONTENTS=""
APP_MACOS=""
APP_RESOURCES=""
APP_BINARY=""
INFO_PLIST=""
TARGET_RESOURCE_BUNDLE=""
TARGET_RESOURCE_BUNDLE_INFO=""
STAGED_METALLIB=""
MLX_RESOURCE_BUNDLE=""
MLX_BUNDLE_CONTENTS=""
MLX_BUNDLE_RESOURCES=""
MLX_BUNDLE_INFO=""
PACKAGED_METALLIB=""
ICON_CATALOG=""
APP_ICON_SET=""
ASSETCATALOG_INFO=""
BACKUP_DIR=""
BACKUP_APP_BUNDLE=""
PUBLISH_STATE="idle"
PUBLISHED_APP_LAUNCH_ATTEMPTED="false"

METALLIB_BYTES="106957102"
METALLIB_SHA256="82be53f327e9a39cb19a18272187187b7636f31989c44ad7ff474f7fe8171974"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'usage: %s [run|debug|--debug|logs|--logs|telemetry|--telemetry|verify|--verify]\n' "$0" >&2
}

validate_mode() {
  if [[ "$#" -gt 1 ]]; then
    usage
    exit 2
  fi

  case "$MODE" in
    run|debug|--debug|logs|--logs|telemetry|--telemetry|verify|--verify)
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

# Invalid arguments must be rejected before stopping the app, building, or signing.
validate_mode "$@"

initialize_staging_paths() {
  mkdir -p "$DIST_DIR"
  STAGING_DIR="$(/usr/bin/mktemp -d "$DIST_DIR/.veloura-lucent-stage.XXXXXX")" ||
    die "unable to create a staging directory inside $DIST_DIR"
  APP_BUNDLE="$STAGING_DIR/$DISPLAY_NAME.app"
  APP_CONTENTS="$APP_BUNDLE/Contents"
  APP_MACOS="$APP_CONTENTS/MacOS"
  APP_RESOURCES="$APP_CONTENTS/Resources"
  APP_BINARY="$APP_MACOS/$BUILD_PRODUCT_NAME"
  INFO_PLIST="$APP_CONTENTS/Info.plist"
  TARGET_RESOURCE_BUNDLE="$APP_RESOURCES/$RESOURCE_BUNDLE_NAME"
  TARGET_RESOURCE_BUNDLE_INFO="$TARGET_RESOURCE_BUNDLE/Info.plist"
  STAGED_METALLIB="$TARGET_RESOURCE_BUNDLE/StemModels/MLX/mlx.metallib"
  MLX_RESOURCE_BUNDLE="$APP_RESOURCES/mlx-swift_Cmlx.bundle"
  MLX_BUNDLE_CONTENTS="$MLX_RESOURCE_BUNDLE/Contents"
  MLX_BUNDLE_RESOURCES="$MLX_BUNDLE_CONTENTS/Resources"
  MLX_BUNDLE_INFO="$MLX_BUNDLE_CONTENTS/Info.plist"
  PACKAGED_METALLIB="$MLX_BUNDLE_RESOURCES/default.metallib"
  ICON_CATALOG="$STAGING_DIR/Assets.xcassets"
  APP_ICON_SET="$ICON_CATALOG/AppIcon.appiconset"
  ASSETCATALOG_INFO="$STAGING_DIR/assetcatalog_generated_info.plist"
}

restore_previous_app() {
  local failed_new_app=""

  [[ "$PUBLISH_STATE" == "backing_up" || \
    "$PUBLISH_STATE" == "old_backed_up" || \
    "$PUBLISH_STATE" == "new_published_with_backup" ]] || return 0
  if [[ "$PUBLISH_STATE" == "backing_up" && \
    ! -e "$BACKUP_APP_BUNDLE" && ! -L "$BACKUP_APP_BUNDLE" ]]; then
    PUBLISH_STATE="idle"
    return 0
  fi
  [[ -n "$BACKUP_APP_BUNDLE" && \
    ( -e "$BACKUP_APP_BUNDLE" || -L "$BACKUP_APP_BUNDLE" ) ]] || {
    PUBLISH_STATE="restore_failed"
    printf 'error: the previous app backup is unavailable: %s\n' "$BACKUP_APP_BUNDLE" >&2
    return 1
  }

  if [[ -e "$FINAL_APP_BUNDLE" || -L "$FINAL_APP_BUNDLE" ]]; then
    failed_new_app="$STAGING_DIR/.failed-published-app"
    if ! /bin/mv "$FINAL_APP_BUNDLE" "$failed_new_app"; then
      PUBLISH_STATE="restore_failed"
      printf 'error: unable to move the failed new app aside; previous app remains at %s\n' \
        "$BACKUP_APP_BUNDLE" >&2
      return 1
    fi
  fi

  if /bin/mv "$BACKUP_APP_BUNDLE" "$FINAL_APP_BUNDLE"; then
    PUBLISH_STATE="restored"
    return 0
  fi

  PUBLISH_STATE="restore_failed"
  printf 'error: unable to restore the previous app; backup remains at %s\n' \
    "$BACKUP_APP_BUNDLE" >&2
  return 1
}

stop_launched_app_for_rollback() {
  local attempt=0

  [[ "$PUBLISHED_APP_LAUNCH_ATTEMPTED" == "true" ]] || return 0

  /usr/bin/pkill -TERM -x "$BUILD_PRODUCT_NAME" >/dev/null 2>&1 || true
  for ((attempt = 0; attempt < 40; attempt += 1)); do
    if ! /usr/bin/pgrep -x "$BUILD_PRODUCT_NAME" >/dev/null 2>&1; then
      PUBLISHED_APP_LAUNCH_ATTEMPTED="false"
      return 0
    fi
    /bin/sleep 0.05
  done

  /usr/bin/pkill -KILL -x "$BUILD_PRODUCT_NAME" >/dev/null 2>&1 || true
  for ((attempt = 0; attempt < 20; attempt += 1)); do
    if ! /usr/bin/pgrep -x "$BUILD_PRODUCT_NAME" >/dev/null 2>&1; then
      PUBLISHED_APP_LAUNCH_ATTEMPTED="false"
      return 0
    fi
    /bin/sleep 0.05
  done

  printf 'error: unable to stop the newly launched app before rollback\n' >&2
  return 1
}

cleanup_on_exit() {
  local status="$?"
  local should_restore_previous="false"
  local should_remove_new="false"

  trap - EXIT
  if [[ "$status" -ne 0 ]]; then
    if [[ "$PUBLISH_STATE" == "backing_up" || \
      "$PUBLISH_STATE" == "old_backed_up" || \
      "$PUBLISH_STATE" == "new_published_with_backup" ]]; then
      should_restore_previous="true"
    elif [[ ( "$PUBLISH_STATE" == "publishing_without_previous" || \
      "$PUBLISH_STATE" == "new_published_without_previous" ) && \
      ( -e "$FINAL_APP_BUNDLE" || -L "$FINAL_APP_BUNDLE" ) ]]; then
      should_remove_new="true"
    fi

    if [[ "$should_restore_previous" == "true" || "$should_remove_new" == "true" ]]; then
      if stop_launched_app_for_rollback; then
        if [[ "$should_restore_previous" == "true" ]]; then
          restore_previous_app || true
        else
          if ! /bin/mv "$FINAL_APP_BUNDLE" "$STAGING_DIR/.failed-published-app"; then
            PUBLISH_STATE="restore_failed"
            printf 'error: unable to remove the failed newly published app: %s\n' \
              "$FINAL_APP_BUNDLE" >&2
          fi
        fi
      else
        PUBLISH_STATE="restore_failed"
      fi
    fi
  fi
  if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
    /bin/rm -rf "$STAGING_DIR"
  fi
  if [[ "$PUBLISH_STATE" != "restore_failed" && -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
    /bin/rm -rf "$BACKUP_DIR"
  fi
  exit "$status"
}

trap cleanup_on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

file_size() {
  /usr/bin/stat -f '%z' "$1"
}

file_sha256() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

verify_asset() {
  local path="$1"
  local expected_bytes="$2"
  local expected_sha256="$3"
  local actual_bytes=""
  local actual_sha256=""

  [[ -f "$path" ]] || die "required packaged asset is missing: $path"
  actual_bytes="$(file_size "$path")"
  [[ "$actual_bytes" == "$expected_bytes" ]] ||
    die "packaged asset size mismatch: $path (expected $expected_bytes, found $actual_bytes)"
  actual_sha256="$(file_sha256 "$path")"
  [[ "$actual_sha256" == "$expected_sha256" ]] ||
    die "packaged asset SHA-256 mismatch: $path (expected $expected_sha256, found $actual_sha256)"
}

write_target_resource_bundle_info() {
  cat >"$TARGET_RESOURCE_BUNDLE_INFO" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>ja</string>
  <key>CFBundleIdentifier</key>
  <string>com.codex.VelouraLucent.Resources</string>
  <key>CFBundleName</key>
  <string>VelouraLucent_VelouraLucent</string>
  <key>CFBundlePackageType</key>
  <string>BNDL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
</dict>
</plist>
PLIST
}

write_mlx_resource_bundle_info() {
  cat >"$MLX_BUNDLE_INFO" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleIdentifier</key>
  <string>org.swift.swiftpm.mlx-swift.Cmlx</string>
  <key>CFBundleName</key>
  <string>mlx-swift_Cmlx</string>
  <key>CFBundlePackageType</key>
  <string>BNDL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.30.6</string>
  <key>CFBundleVersion</key>
  <string>0.30.6</string>
</dict>
</plist>
PLIST
}

stage_stem_runtime_assets() {
  [[ -d "$TARGET_RESOURCE_BUNDLE" ]] ||
    die "SwiftPM resource bundle is missing: $TARGET_RESOURCE_BUNDLE"
  verify_asset "$STAGED_METALLIB" "$METALLIB_BYTES" "$METALLIB_SHA256"

  [[ ! -e "$TARGET_RESOURCE_BUNDLE/StemModels/htdemucs/htdemucs.safetensors" ]] ||
    die "downloadable AI model weights must not be packaged in the application"
  [[ ! -e "$TARGET_RESOURCE_BUNDLE/StemModels/htdemucs/htdemucs_config.json" ]] ||
    die "downloadable AI model configuration must not be packaged in the application"

  mkdir -p "$MLX_BUNDLE_RESOURCES"
  /bin/mv "$STAGED_METALLIB" "$PACKAGED_METALLIB"
  /bin/rmdir "$TARGET_RESOURCE_BUNDLE/StemModels/MLX"
  write_target_resource_bundle_info
  write_mlx_resource_bundle_info
}

verify_packaged_stem_layout() {
  local metallib_count=""

  verify_asset "$PACKAGED_METALLIB" "$METALLIB_BYTES" "$METALLIB_SHA256"
  [[ ! -e "$STAGED_METALLIB" ]] || die "duplicate mlx.metallib remained in the target resource bundle"
  if /usr/bin/find "$APP_BUNDLE" -type f \
    \( -name 'htdemucs.safetensors' -o -name 'htdemucs_config.json' \) \
    -print -quit | /usr/bin/grep -q .; then
    die "downloadable AI model assets must not be present in the packaged application"
  fi
  [[ -f "$TARGET_RESOURCE_BUNDLE/ThirdPartyNotices/README.md" ]] ||
    die "Stem Mode third-party notices are missing from the packaged app"
  /usr/bin/diff -qr \
    "$ROOT_DIR/Sources/VelouraLucent/Resources/ThirdPartyNotices" \
    "$TARGET_RESOURCE_BUNDLE/ThirdPartyNotices" >/dev/null ||
    die "packaged third-party notices differ from the verified source inventory"
  /usr/bin/cmp -s \
    "$ROOT_DIR/Sources/VelouraLucent/Resources/StemModels/stem-model-manifest.json" \
    "$TARGET_RESOURCE_BUNDLE/StemModels/stem-model-manifest.json" ||
    die "packaged Stem Mode manifest differs from the verified source manifest"
  /usr/bin/plutil -lint "$TARGET_RESOURCE_BUNDLE_INFO" "$MLX_BUNDLE_INFO" >/dev/null

  metallib_count="$(
    /usr/bin/find "$APP_BUNDLE" -type f -name '*.metallib' -print |
      /usr/bin/wc -l |
      /usr/bin/tr -d '[:space:]'
  )"
  [[ "$metallib_count" == "1" ]] ||
    die "expected exactly one packaged metallib, found $metallib_count"
}

verify_packaged_layout() {
  local app_root_entry_count=""

  verify_packaged_stem_layout
  /usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
  app_root_entry_count="$(
    /usr/bin/find "$APP_BUNDLE" -mindepth 1 -maxdepth 1 -print |
      /usr/bin/wc -l |
      /usr/bin/tr -d '[:space:]'
  )"
  [[ "$app_root_entry_count" == "1" && -d "$APP_CONTENTS" ]] ||
    die "the app bundle root must contain only Contents before signing"
}

sign_app_bundle() {
  local identity="${VELOURA_CODESIGN_IDENTITY:--}"
  local -a nested_flags=(--force --sign "$identity")
  local -a app_flags=(--force --sign "$identity")

  if [[ "$identity" != "-" ]]; then
    nested_flags+=(--timestamp)
    app_flags+=(--options runtime --timestamp)
  fi

  /usr/bin/codesign "${nested_flags[@]}" "$TARGET_RESOURCE_BUNDLE"
  /usr/bin/codesign "${nested_flags[@]}" "$MLX_RESOURCE_BUNDLE"
  /usr/bin/codesign "${app_flags[@]}" "$APP_BUNDLE"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
}

publish_app_bundle() {
  local had_previous="false"

  BACKUP_DIR="$(/usr/bin/mktemp -d "$DIST_DIR/.veloura-lucent-backup.XXXXXX")" ||
    die "unable to create an app backup directory inside $DIST_DIR"
  BACKUP_APP_BUNDLE="$BACKUP_DIR/$DISPLAY_NAME.app"

  if [[ -e "$FINAL_APP_BUNDLE" || -L "$FINAL_APP_BUNDLE" ]]; then
    PUBLISH_STATE="backing_up"
    if ! /bin/mv "$FINAL_APP_BUNDLE" "$BACKUP_APP_BUNDLE"; then
      PUBLISH_STATE="idle"
      die "unable to back up the currently published app"
    fi
    PUBLISH_STATE="old_backed_up"
    had_previous="true"
  else
    PUBLISH_STATE="publishing_without_previous"
  fi

  if /bin/mv "$APP_BUNDLE" "$FINAL_APP_BUNDLE"; then
    if [[ "$had_previous" == "true" ]]; then
      PUBLISH_STATE="new_published_with_backup"
    else
      PUBLISH_STATE="new_published_without_previous"
    fi
  else
    restore_previous_app || true
    die "unable to publish the signed app; the previous app was restored when available"
  fi

}

finalize_published_app() {
  [[ "$PUBLISH_STATE" == "new_published_with_backup" || \
    "$PUBLISH_STATE" == "new_published_without_previous" ]] ||
    die "cannot finalize an app that has not been published and verified"

  # From this point the new app is accepted; cleanup failures must not restore the old app.
  PUBLISH_STATE="new_published"
  if [[ -n "$BACKUP_APP_BUNDLE" && \
    ( -e "$BACKUP_APP_BUNDLE" || -L "$BACKUP_APP_BUNDLE" ) ]]; then
    /bin/rm -rf "$BACKUP_APP_BUNDLE"
  fi
  if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
    /bin/rmdir "$BACKUP_DIR"
  fi
  BACKUP_DIR=""
  BACKUP_APP_BUNDLE=""
  if [[ "$LEGACY_APP_BUNDLE" != "$FINAL_APP_BUNDLE" ]]; then
    /bin/rm -rf "$LEGACY_APP_BUNDLE"
  fi
}

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

"$ROOT_DIR/script/prepare_stem_models.sh" --prepare-packaging
swift build -c release --force-resolved-versions
# Keep the post-build check as a second fail-closed boundary before distributable staging.
"$ROOT_DIR/script/prepare_stem_models.sh" --verify-packaging
BUILD_DIR="$(swift build -c release --force-resolved-versions --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$BUILD_PRODUCT_NAME"
RESOURCE_BUNDLE="$BUILD_DIR/$RESOURCE_BUNDLE_NAME"

[[ -f "$BUILD_BINARY" ]] || die "built executable is missing: $BUILD_BINARY"
[[ -d "$RESOURCE_BUNDLE" ]] || die "built SwiftPM resource bundle is missing: $RESOURCE_BUNDLE"

initialize_staging_paths
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
/usr/bin/ditto "$RESOURCE_BUNDLE" "$TARGET_RESOURCE_BUNDLE"
stage_stem_runtime_assets
generate_app_icon_assets
if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$APP_RESOURCES/$RUNTIME_ICON_NAME"
fi
if [[ -d "$APP_LOCALIZATION_SOURCE" ]]; then
  cp -R "$APP_LOCALIZATION_SOURCE" "$APP_RESOURCES/ja.lproj"
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
  <key>CFBundleDevelopmentRegion</key>
  <string>ja</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>ja</string>
  </array>
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

verify_packaged_layout
sign_app_bundle
publish_app_bundle
/usr/bin/codesign --verify --deep --strict --verbose=2 "$FINAL_APP_BUNDLE"

open_app() {
  PUBLISHED_APP_LAUNCH_ATTEMPTED="true"
  /usr/bin/open -n -F "$FINAL_APP_BUNDLE" --args -ApplePersistenceIgnoreState YES
}

case "$MODE" in
  run)
    open_app
    finalize_published_app
    ;;
  --debug|debug)
    finalize_published_app
    lldb -- "$FINAL_APP_BINARY"
    ;;
  --logs|logs)
    open_app
    finalize_published_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$BUILD_PRODUCT_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    finalize_published_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    verify_pid=""
    verify_command=""
    open_app
    sleep 1
    verify_pid="$(pgrep -x "$BUILD_PRODUCT_NAME" | /usr/bin/head -n 1 || true)"
    [[ -n "$verify_pid" ]] || die "published app did not stay running during verification"
    verify_command="$(/bin/ps -p "$verify_pid" -o command=)"
    [[ "$verify_command" == "$FINAL_APP_BINARY"* ]] ||
      die "verification found an unexpected $BUILD_PRODUCT_NAME process: $verify_command"
    finalize_published_app
    ;;
esac
