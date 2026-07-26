#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: script/prepare_stem_models.sh [--prepare-packaging | --verify-only | --verify-packaging]

Without arguments:
  Reuse every valid asset, download the fixed htdemucs weights/config when
  needed, and build mlx.metallib from the fixed mlx-swift checkout when needed.

--verify-only:
  Perform byte-count and SHA-256 validation without downloading or compiling.

--prepare-packaging:
  Resolve only the fixed SwiftPM runtime checkout when needed, then build or
  reuse the bundled mlx.metallib and validate the third-party notices. This
  mode never reads, downloads, or changes the AI model cache.

--verify-packaging:
  Validate only the signed manifest, fixed dependencies, third-party notices,
  and bundled mlx.metallib required to create the application. AI model files
  are deliberately excluded from the application package.
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

file_size() {
  local path="$1"
  local value=""

  if value="$(stat -f '%z' "$path" 2>/dev/null)" && [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
    return
  fi

  if value="$(stat -c '%s' "$path" 2>/dev/null)" && [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
    return
  fi

  die "could not determine file size: $path"
}

file_sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

asset_matches() {
  local path="$1"
  local expected_bytes="$2"
  local expected_sha256="$3"

  [[ -f "$path" ]] || return 1
  [[ "$(file_size "$path")" == "$expected_bytes" ]] || return 1
  [[ "$(file_sha256 "$path")" == "$expected_sha256" ]] || return 1
}

show_asset_mismatch() {
  local path="$1"
  local expected_bytes="$2"
  local expected_sha256="$3"

  if [[ ! -f "$path" ]]; then
    printf 'error: required asset is missing: %s\n' "$path" >&2
    printf 'expected bytes: %s\n' "$expected_bytes" >&2
    printf 'expected sha256: %s\n' "$expected_sha256" >&2
    return
  fi

  printf 'error: asset validation failed: %s\n' "$path" >&2
  printf 'expected bytes: %s\n' "$expected_bytes" >&2
  printf 'actual bytes:   %s\n' "$(file_size "$path")" >&2
  printf 'expected sha256: %s\n' "$expected_sha256" >&2
  printf 'actual sha256:   %s\n' "$(file_sha256 "$path")" >&2
}

verify_asset_or_die() {
  local path="$1"
  local expected_bytes="$2"
  local expected_sha256="$3"

  if ! asset_matches "$path" "$expected_bytes" "$expected_sha256"; then
    show_asset_mismatch "$path" "$expected_bytes" "$expected_sha256"
    die "Stem Mode asset verification stopped"
  fi

  printf 'verified: %s\n' "$path"
}

manifest_value_for_file() {
  local manifest_file="$1"
  local key_path="$2"
  local actual_value=""

  if ! actual_value="$(/usr/bin/plutil -extract "$key_path" raw "$manifest_file" 2>/dev/null)"; then
    die "manifest field is missing or invalid: $manifest_file:$key_path"
  fi

  printf '%s\n' "$actual_value"
}

verify_manifest_value_for_file() {
  local manifest_file="$1"
  local key_path="$2"
  local expected_value="$3"
  local actual_value=""

  actual_value="$(manifest_value_for_file "$manifest_file" "$key_path")"
  [[ "$actual_value" == "$expected_value" ]] ||
    die "manifest field mismatch for $manifest_file:$key_path: expected $expected_value, found $actual_value"
}

verify_array_count_for_file() {
  local manifest_file="$1"
  local array_key="$2"
  local expected_count="$3"
  local actual_count=""

  actual_count="$(manifest_value_for_file "$manifest_file" "$array_key")"
  [[ "$actual_count" =~ ^[0-9]+$ ]] ||
    die "manifest array count is invalid: $manifest_file:$array_key:$actual_count"
  [[ "$actual_count" == "$expected_count" ]] ||
    die "manifest array count mismatch for $manifest_file:$array_key: expected $expected_count, found $actual_count"
}

verify_manifest_value() {
  verify_manifest_value_for_file "$MANIFEST_PATH" "$1" "$2"
}

verify_manifest_value_absent() {
  local key_path="$1"

  if /usr/bin/plutil -extract "$key_path" raw "$MANIFEST_PATH" >/dev/null 2>&1; then
    die "manifest field must be absent: $key_path"
  fi
}

verify_manifest_array_count() {
  verify_array_count_for_file "$MANIFEST_PATH" "$1" "$2" "${3:-}"
}

verify_manifest_contract() {
  require_command /usr/bin/plutil

  verify_manifest_value "schemaVersion" "2"
  verify_manifest_value "assetSetIdentifier" "htdemucs-$MODEL_REVISION"
  verify_manifest_value "model.name" "Demucs v4 htdemucs"
  verify_manifest_value "model.repo" "$MODEL_REPO"
  verify_manifest_value "model.revision" "$MODEL_REVISION"
  verify_manifest_value "model.licenseMetadata" "mit"

  verify_manifest_array_count "runtimePins" "7" "name"
  verify_manifest_value "runtimePins.0.name" "demucs-mlx-swift"
  verify_manifest_value "runtimePins.0.repo" "https://github.com/kylehowells/demucs-mlx-swift.git"
  verify_manifest_value_absent "runtimePins.0.version"
  verify_manifest_value "runtimePins.0.revision" "c81c47178828db2d8bc66e64f80c745c64abdc94"
  verify_manifest_value "runtimePins.1.name" "mlx-swift"
  verify_manifest_value "runtimePins.1.repo" "https://github.com/ml-explore/mlx-swift.git"
  verify_manifest_value "runtimePins.1.version" "0.30.6"
  verify_manifest_value "runtimePins.1.revision" "$MLX_SWIFT_REVISION"
  verify_manifest_value "runtimePins.2.name" "swift-transformers"
  verify_manifest_value "runtimePins.2.repo" "https://github.com/huggingface/swift-transformers.git"
  verify_manifest_value "runtimePins.2.version" "1.1.6"
  verify_manifest_value "runtimePins.2.revision" "573e5c9036c2f136b3a8a071da8e8907322403d0"
  verify_manifest_value "runtimePins.3.name" "swift-jinja"
  verify_manifest_value "runtimePins.3.repo" "https://github.com/huggingface/swift-jinja.git"
  verify_manifest_value "runtimePins.3.version" "2.3.2"
  verify_manifest_value "runtimePins.3.revision" "f731f03bf746481d4fda07f817c3774390c4d5b9"
  verify_manifest_value "runtimePins.4.name" "swift-collections"
  verify_manifest_value "runtimePins.4.repo" "https://github.com/apple/swift-collections.git"
  verify_manifest_value "runtimePins.4.version" "1.4.0"
  verify_manifest_value "runtimePins.4.revision" "8d9834a6189db730f6264db7556a7ffb751e99ee"
  verify_manifest_value "runtimePins.5.name" "swift-argument-parser"
  verify_manifest_value "runtimePins.5.repo" "https://github.com/apple/swift-argument-parser"
  verify_manifest_value "runtimePins.5.version" "1.8.2"
  verify_manifest_value "runtimePins.5.revision" "6a52f3251125d74daf04fcbd5e6f08a75d074382"
  verify_manifest_value "runtimePins.6.name" "swift-numerics"
  verify_manifest_value "runtimePins.6.repo" "https://github.com/apple/swift-numerics"
  verify_manifest_value "runtimePins.6.version" "1.1.1"
  verify_manifest_value "runtimePins.6.revision" "0c0290ff6b24942dadb83a929ffaaa1481df04a2"

  verify_manifest_value "audioContract.sampleRateHz" "44100"
  verify_manifest_value "audioContract.channelCount" "2"
  verify_manifest_value "audioContract.channelLayout" "stereo"
  verify_manifest_value "audioContract.scalarType" "float32"
  verify_manifest_value "audioContract.inputTensorLayout" "channel-major"
  verify_manifest_value "audioContract.outputTensorLayout" "source-major"
  verify_manifest_value "audioContract.channelLayoutWithinSource" "channel-major"
  verify_manifest_array_count "audioContract.sourceOrder" "4"
  verify_manifest_value "audioContract.sourceOrder.0" "drums"
  verify_manifest_value "audioContract.sourceOrder.1" "bass"
  verify_manifest_value "audioContract.sourceOrder.2" "other"
  verify_manifest_value "audioContract.sourceOrder.3" "vocals"

  verify_manifest_value "downloadPolicy.requiresExplicitUserConfirmation" "true"
  verify_manifest_value "downloadPolicy.revisionResponseHeader" "X-Repo-Commit"
  verify_manifest_array_count "downloadPolicy.allowedRedirectHosts" "2"
  verify_manifest_value "downloadPolicy.allowedRedirectHosts.0" "huggingface.co"
  verify_manifest_value "downloadPolicy.allowedRedirectHosts.1" "cas-bridge.xethub.hf.co"

  verify_manifest_array_count "downloadableModelAssets" "2" "kind"
  verify_manifest_value "downloadableModelAssets.0.kind" "modelWeights"
  verify_manifest_value "downloadableModelAssets.0.downloadURL" "$MODEL_BASE_URL/htdemucs.safetensors"
  verify_manifest_value "downloadableModelAssets.0.installationRelativePath" "htdemucs/htdemucs.safetensors"
  verify_manifest_value "downloadableModelAssets.0.byteCount" "$WEIGHTS_BYTES"
  verify_manifest_value "downloadableModelAssets.0.sha256" "$WEIGHTS_SHA256"
  verify_manifest_value "downloadableModelAssets.1.kind" "modelConfiguration"
  verify_manifest_value "downloadableModelAssets.1.downloadURL" "$MODEL_BASE_URL/htdemucs_config.json"
  verify_manifest_value "downloadableModelAssets.1.installationRelativePath" "htdemucs/htdemucs_config.json"
  verify_manifest_value "downloadableModelAssets.1.byteCount" "$CONFIG_BYTES"
  verify_manifest_value "downloadableModelAssets.1.sha256" "$CONFIG_SHA256"

  verify_manifest_array_count "bundledRuntimeAssets" "1" "kind"
  verify_manifest_value "bundledRuntimeAssets.0.kind" "metalLibrary"
  verify_manifest_value "bundledRuntimeAssets.0.resourceRelativePath" "StemModels/MLX/mlx.metallib"
  verify_manifest_value "bundledRuntimeAssets.0.runtimeRelativePath" "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
  verify_manifest_value "bundledRuntimeAssets.0.byteCount" "$METAL_BYTES"
  verify_manifest_value "bundledRuntimeAssets.0.sha256" "$METAL_SHA256"
  verify_manifest_value_absent "assets"

  verify_manifest_value "metalLibraryBuildProvenance.sourceRepo" "https://github.com/ml-explore/mlx-swift.git"
  verify_manifest_value "metalLibraryBuildProvenance.sourceVersion" "0.30.6"
  verify_manifest_value "metalLibraryBuildProvenance.sourceRevision" "$MLX_SWIFT_REVISION"
  verify_manifest_value "metalLibraryBuildProvenance.sourceDirectory" "Source/Cmlx/mlx/mlx/backend/metal/kernels"
  verify_manifest_value "metalLibraryBuildProvenance.sourceSelection" "all *.metal files except *_nax.metal, sorted with LC_ALL=C"
  verify_manifest_value "metalLibraryBuildProvenance.sourceFileCount" "32"
  verify_manifest_value "metalLibraryBuildProvenance.compilerCommand" "xcrun -sdk macosx metal"
  verify_manifest_value "metalLibraryBuildProvenance.linkerCommand" "xcrun -sdk macosx metallib"
  verify_manifest_array_count "metalLibraryBuildProvenance.compilerFlags" "7"
  verify_manifest_value "metalLibraryBuildProvenance.compilerFlags.0" "-x"
  verify_manifest_value "metalLibraryBuildProvenance.compilerFlags.1" "metal"
  verify_manifest_value "metalLibraryBuildProvenance.compilerFlags.2" "-Wall"
  verify_manifest_value "metalLibraryBuildProvenance.compilerFlags.3" "-Wextra"
  verify_manifest_value "metalLibraryBuildProvenance.compilerFlags.4" "-fno-fast-math"
  verify_manifest_value "metalLibraryBuildProvenance.compilerFlags.5" "-Wno-c++17-extensions"
  verify_manifest_value "metalLibraryBuildProvenance.compilerFlags.6" "-Wno-c++20-extensions"
  verify_manifest_array_count "metalLibraryBuildProvenance.includeDirectories" "2"
  verify_manifest_value "metalLibraryBuildProvenance.includeDirectories.0" "Source/Cmlx/mlx/mlx/backend/metal/kernels"
  verify_manifest_value "metalLibraryBuildProvenance.includeDirectories.1" "Source/Cmlx/mlx"
  verify_manifest_value "metalLibraryBuildProvenance.verifiedToolchain.xcodeVersion" "26.6"
  verify_manifest_value "metalLibraryBuildProvenance.verifiedToolchain.xcodeBuildVersion" "17F113"
  verify_manifest_value "metalLibraryBuildProvenance.verifiedToolchain.macosSdkVersion" "26.5"
  verify_manifest_value "metalLibraryBuildProvenance.verifiedToolchain.metalVersion" "Apple metal version 32023.883 (metalfe-32023.883)"
  verify_manifest_value "metalLibraryBuildProvenance.verifiedToolchain.metallibVersion" "AIR-LLD 32023.883 (metalfe-32023.883) (compatible with legacy metallib linker)"
}

verify_package_resolved_pin() {
  local index="$1"
  local identity="$2"
  local location="$3"
  local revision="$4"
  local version="$5"
  local prefix="pins.$index"

  verify_manifest_value_for_file "$PACKAGE_RESOLVED_PATH" "$prefix.identity" "$identity"
  verify_manifest_value_for_file "$PACKAGE_RESOLVED_PATH" "$prefix.kind" "remoteSourceControl"
  verify_manifest_value_for_file "$PACKAGE_RESOLVED_PATH" "$prefix.location" "$location"
  verify_manifest_value_for_file "$PACKAGE_RESOLVED_PATH" "$prefix.state.revision" "$revision"

  if [[ "$version" == "__absent__" ]]; then
    if /usr/bin/plutil -extract "$prefix.state.version" raw "$PACKAGE_RESOLVED_PATH" >/dev/null 2>&1; then
      die "Package.resolved field must be absent: $prefix.state.version"
    fi
  else
    verify_manifest_value_for_file "$PACKAGE_RESOLVED_PATH" "$prefix.state.version" "$version"
  fi
}

verify_package_resolved_contract() {
  [[ -f "$PACKAGE_RESOLVED_PATH" ]] ||
    die "missing fixed SwiftPM lockfile: $PACKAGE_RESOLVED_PATH"

  verify_manifest_value_for_file "$PACKAGE_RESOLVED_PATH" "version" "3"
  verify_array_count_for_file "$PACKAGE_RESOLVED_PATH" "pins" "6" "identity"
  verify_package_resolved_pin \
    "0" \
    "mlx-swift" \
    "https://github.com/ml-explore/mlx-swift.git" \
    "6ba4827fb82c97d012eec9ab4b2de21f85c3b33d" \
    "0.30.6"
  verify_package_resolved_pin \
    "1" \
    "swift-argument-parser" \
    "https://github.com/apple/swift-argument-parser" \
    "6a52f3251125d74daf04fcbd5e6f08a75d074382" \
    "1.8.2"
  verify_package_resolved_pin \
    "2" \
    "swift-collections" \
    "https://github.com/apple/swift-collections.git" \
    "8d9834a6189db730f6264db7556a7ffb751e99ee" \
    "1.4.0"
  verify_package_resolved_pin \
    "3" \
    "swift-jinja" \
    "https://github.com/huggingface/swift-jinja.git" \
    "f731f03bf746481d4fda07f817c3774390c4d5b9" \
    "2.3.2"
  verify_package_resolved_pin \
    "4" \
    "swift-numerics" \
    "https://github.com/apple/swift-numerics" \
    "0c0290ff6b24942dadb83a929ffaaa1481df04a2" \
    "1.1.1"
  verify_package_resolved_pin \
    "5" \
    "swift-transformers" \
    "https://github.com/huggingface/swift-transformers.git" \
    "573e5c9036c2f136b3a8a071da8e8907322403d0" \
    "1.1.6"

  printf 'verified SwiftPM lockfile: 6 fixed remote dependencies\n'
}

verify_vendored_demucs_contract() {
  local provenance="$VENDORED_DEMUCS_DIR/VENDORED_FROM.md"
  local policy="$VENDORED_DEMUCS_DIR/Sources/DemucsMLX/DemucsModelResolutionPolicy.swift"

  [[ -f "$VENDORED_DEMUCS_DIR/Package.swift" ]] ||
    die "missing vendored demucs package: $VENDORED_DEMUCS_DIR"
  [[ -f "$provenance" ]] || die "missing vendored demucs provenance: $provenance"
  [[ -f "$policy" ]] || die "missing vendored Demucs local-only policy: $policy"
  /usr/bin/grep -Fq 'Upstream commit: `c81c47178828db2d8bc66e64f80c745c64abdc94`' "$provenance" ||
    die "vendored demucs upstream revision does not match the fixed contract"
  /usr/bin/grep -Fq 'case localOnly' "$policy" ||
    die "vendored demucs package does not expose the local-only model policy"
  /usr/bin/grep -Fq '.package(path: "Vendor/demucs-mlx-swift")' "$ROOT_DIR/Package.swift" ||
    die "root Package.swift is not using the reviewed vendored demucs package"

  verify_vendored_demucs_inventory
  printf 'verified vendored demucs source, reviewed inventory, and local-only model policy\n'
}

verify_vendored_demucs_inventory() {
  local inventory="$VENDORED_DEMUCS_DIR/VENDORED_INVENTORY.sha256"
  local expected_inventory_sha256="af2d5babe1a71cc5260d27401a7e9afc5a850e2d0406e6325f64b569a9c4e085"
  local actual_inventory_sha256=""
  local inventory_lines=""
  local invalid_lines=""
  local expected_paths=""
  local sorted_unique_expected_paths=""
  local actual_paths=""
  local unsafe_path=""
  local unexpected_symlink=""
  local verification_output=""

  [[ -f "$inventory" ]] || die "missing reviewed vendored source inventory: $inventory"
  actual_inventory_sha256="$(file_sha256 "$inventory")"
  [[ "$actual_inventory_sha256" == "$expected_inventory_sha256" ]] ||
    die "reviewed vendored source inventory SHA-256 mismatch: expected $expected_inventory_sha256, found $actual_inventory_sha256"

  inventory_lines="$(<"$inventory")"
  [[ -n "$inventory_lines" ]] || die "reviewed vendored source inventory is empty"
  invalid_lines="$(
    printf '%s\n' "$inventory_lines" |
      /usr/bin/grep -Ev '^[0-9a-f]{64}  \./[^/].*$' || true
  )"
  [[ -z "$invalid_lines" ]] ||
    die "reviewed vendored source inventory has an invalid entry: $(printf '%s\n' "$invalid_lines" | /usr/bin/head -n 1)"

  expected_paths="$(printf '%s\n' "$inventory_lines" | /usr/bin/sed -E 's/^[0-9a-f]{64}  //')"
  while IFS= read -r unsafe_path; do
    case "$unsafe_path" in
      ./|./../*|*/../*|*/..|*//*|*\\*)
        die "reviewed vendored source inventory has an unsafe path: $unsafe_path"
        ;;
    esac
  done <<<"$expected_paths"

  sorted_unique_expected_paths="$(printf '%s\n' "$expected_paths" | LC_ALL=C /usr/bin/sort -u)"
  [[ "$expected_paths" == "$sorted_unique_expected_paths" ]] ||
    die "reviewed vendored source inventory paths must be unique and LC_ALL=C sorted"

  unexpected_symlink="$(
    cd "$VENDORED_DEMUCS_DIR"
    /usr/bin/find . \
      \( -path './.build' -o -path './.git' \) -prune -o \
      -type l -print -quit
  )"
  [[ -z "$unexpected_symlink" ]] ||
    die "reviewed vendored source contains an unapproved symbolic link: $unexpected_symlink"

  actual_paths="$(
    cd "$VENDORED_DEMUCS_DIR"
    /usr/bin/find . \
      \( -path './.build' -o -path './.git' \) -prune -o \
      -type f \
      ! -name '.DS_Store' \
      ! -path './VENDORED_INVENTORY.sha256' -print |
      LC_ALL=C /usr/bin/sort
  )"
  [[ "$actual_paths" == "$expected_paths" ]] ||
    die "vendored demucs file set differs from the reviewed inventory"

  if ! verification_output="$(
    cd "$VENDORED_DEMUCS_DIR"
    /usr/bin/shasum -a 256 -c VENDORED_INVENTORY.sha256 2>&1
  )"; then
    printf '%s\n' "$verification_output" >&2
    die "vendored demucs file content differs from the reviewed inventory"
  fi

  printf 'verified reviewed vendored source inventory: %s files\n' \
    "$(printf '%s\n' "$expected_paths" | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')"
}

verify_third_party_notices() {
  local index=0
  local relative_path=""
  local expected_bytes=""
  local expected_sha256=""
  local expected_paths=""
  local actual_paths=""
  local -a notice_paths=()

  [[ -f "$NOTICE_MANIFEST_PATH" ]] ||
    die "missing tracked third-party notice manifest: $NOTICE_MANIFEST_PATH"

  verify_manifest_value_for_file "$NOTICE_MANIFEST_PATH" "schemaVersion" "1"
  verify_array_count_for_file "$NOTICE_MANIFEST_PATH" "notices" "18" "relativePath"

  for ((index = 0; index < 18; index += 1)); do
    relative_path="$(manifest_value_for_file "$NOTICE_MANIFEST_PATH" "notices.$index.relativePath")"
    expected_bytes="$(manifest_value_for_file "$NOTICE_MANIFEST_PATH" "notices.$index.byteCount")"
    expected_sha256="$(manifest_value_for_file "$NOTICE_MANIFEST_PATH" "notices.$index.sha256")"

    case "$relative_path" in
      ""|/*|../*|*/../*|*/..)
        die "unsafe third-party notice relativePath: $relative_path"
        ;;
    esac

    notice_paths+=("$relative_path")
    verify_asset_or_die "$NOTICE_ROOT/$relative_path" "$expected_bytes" "$expected_sha256"
  done

  expected_paths="$(printf '%s\n' "${notice_paths[@]}" | LC_ALL=C sort)"
  actual_paths="$(
    find "$NOTICE_ROOT" -type f \
      ! -path "$NOTICE_ROOT/README.md" \
      ! -path "$NOTICE_MANIFEST_PATH" |
      while IFS= read -r notice_file; do
        printf '%s\n' "${notice_file#"$NOTICE_ROOT/"}"
      done |
      LC_ALL=C sort
  )"

  [[ "$actual_paths" == "$expected_paths" ]] ||
    die "third-party notice file set does not match third-party-notices-manifest.json"

  printf 'verified third-party notices: 18 files\n'
}

download_and_verify() {
  local remote_name="$1"
  local destination="$2"
  local expected_bytes="$3"
  local expected_sha256="$4"
  local url="$MODEL_BASE_URL/$remote_name"

  printf 'downloading fixed model asset: %s\n' "$remote_name"
  curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --retry 3 \
    --retry-delay 2 \
    --proto '=https' \
    --tlsv1.2 \
    --output "$destination" \
    "$url"

  if ! asset_matches "$destination" "$expected_bytes" "$expected_sha256"; then
    show_asset_mismatch "$destination" "$expected_bytes" "$expected_sha256"
    die "downloaded asset did not match the fixed manifest"
  fi
}

expected_metal_source_list() {
  cat <<'SOURCES'
arange.metal
arg_reduce.metal
binary.metal
binary_two.metal
conv.metal
copy.metal
fence.metal
fft.metal
fp_quantized.metal
gemv.metal
gemv_masked.metal
layer_norm.metal
logsumexp.metal
quantized.metal
random.metal
reduce.metal
rms_norm.metal
rope.metal
scaled_dot_product_attention.metal
scan.metal
softmax.metal
sort.metal
steel/attn/kernels/steel_attention.metal
steel/conv/kernels/steel_conv.metal
steel/conv/kernels/steel_conv_general.metal
steel/gemm/kernels/steel_gemm_fused.metal
steel/gemm/kernels/steel_gemm_gather.metal
steel/gemm/kernels/steel_gemm_masked.metal
steel/gemm/kernels/steel_gemm_segmented.metal
steel/gemm/kernels/steel_gemm_splitk.metal
ternary.metal
unary.metal
SOURCES
}

verify_metal_toolchain() {
  local actual_xcode=""
  local actual_sdk=""
  local actual_metal=""
  local actual_metallib=""

  require_command xcodebuild
  require_command xcrun

  if ! xcrun --find metal >/dev/null 2>&1 || ! xcrun --find metallib >/dev/null 2>&1; then
    die "Metal Toolchain is unavailable; run: xcodebuild -downloadComponent MetalToolchain"
  fi

  actual_xcode="$(xcodebuild -version)"
  actual_sdk="$(xcrun --sdk macosx --show-sdk-version)"
  actual_metal="$(xcrun -sdk macosx metal --version 2>&1 | sed -n '1p')"
  actual_metallib="$(xcrun -sdk macosx metallib --version 2>&1 | sed -n '1p')"

  if [[ "$actual_xcode" != $'Xcode 26.6\nBuild version 17F113' ]]; then
    printf 'error: expected Xcode 26.6 / 17F113, found:\n%s\n' "$actual_xcode" >&2
    die "Metal build provenance does not match stem-model-manifest.json"
  fi

  [[ "$actual_sdk" == "26.5" ]] ||
    die "expected macOS SDK 26.5, found $actual_sdk"

  [[ "$actual_metal" == "Apple metal version 32023.883 (metalfe-32023.883)" ]] ||
    die "unexpected Metal compiler version: $actual_metal"

  [[ "$actual_metallib" == "AIR-LLD 32023.883 (metalfe-32023.883) (compatible with legacy metallib linker)" ]] ||
    die "unexpected metallib linker version: $actual_metallib"
}

prepare_downloaded_models() {
  local staged_weights=""
  local staged_config=""

  if asset_matches "$WEIGHTS_PATH" "$WEIGHTS_BYTES" "$WEIGHTS_SHA256"; then
    printf 'reusing verified asset: %s\n' "$WEIGHTS_PATH"
  else
    if [[ -e "$WEIGHTS_PATH" ]]; then
      show_asset_mismatch "$WEIGHTS_PATH" "$WEIGHTS_BYTES" "$WEIGHTS_SHA256"
      printf 'invalid existing file will be replaced only after a valid download\n' >&2
    fi
    require_command curl
    staged_weights="$STAGING_DIR/htdemucs.safetensors"
    download_and_verify \
      "htdemucs.safetensors" \
      "$staged_weights" \
      "$WEIGHTS_BYTES" \
      "$WEIGHTS_SHA256"
  fi

  if asset_matches "$CONFIG_PATH" "$CONFIG_BYTES" "$CONFIG_SHA256"; then
    printf 'reusing verified asset: %s\n' "$CONFIG_PATH"
  else
    if [[ -e "$CONFIG_PATH" ]]; then
      show_asset_mismatch "$CONFIG_PATH" "$CONFIG_BYTES" "$CONFIG_SHA256"
      printf 'invalid existing file will be replaced only after a valid download\n' >&2
    fi
    require_command curl
    staged_config="$STAGING_DIR/htdemucs_config.json"
    download_and_verify \
      "htdemucs_config.json" \
      "$staged_config" \
      "$CONFIG_BYTES" \
      "$CONFIG_SHA256"
  fi

  mkdir -p "$MODEL_DIR"
  if [[ -n "$staged_weights" ]]; then
    mv -f "$staged_weights" "$WEIGHTS_PATH"
    printf 'installed atomically: %s\n' "$WEIGHTS_PATH"
  fi
  if [[ -n "$staged_config" ]]; then
    mv -f "$staged_config" "$CONFIG_PATH"
    printf 'installed atomically: %s\n' "$CONFIG_PATH"
  fi
}

prepare_metal_library() {
  local actual_revision=""
  local expected_sources=""
  local actual_sources=""
  local relative_source=""
  local source=""
  local key=""
  local output_air=""
  local output_metallib="$STAGING_DIR/mlx.metallib"
  local compiler_error="$STAGING_DIR/metal.err"
  local -a metal_sources=()
  local -a air_files=()
  local -a metal_flags=(
    -x
    metal
    -Wall
    -Wextra
    -fno-fast-math
    -Wno-c++17-extensions
    -Wno-c++20-extensions
  )

  if asset_matches "$METAL_PATH" "$METAL_BYTES" "$METAL_SHA256"; then
    printf 'reusing verified asset: %s\n' "$METAL_PATH"
    return
  fi

  if [[ -e "$METAL_PATH" ]]; then
    show_asset_mismatch "$METAL_PATH" "$METAL_BYTES" "$METAL_SHA256"
    printf 'invalid existing file will be replaced only after a verified build\n' >&2
  fi

  require_command find
  require_command git
  require_command shasum
  require_command sort
  require_command sed
  require_command awk

  if [[ ! -d "$MLX_SWIFT_DIR" ]]; then
    require_command swift
    printf 'resolving fixed SwiftPM runtime dependencies without touching AI model assets\n'
    (
      cd "$ROOT_DIR"
      swift package --force-resolved-versions resolve
    )
    # Fail closed if dependency resolution changed any fixed pin.
    verify_package_resolved_contract
  fi
  [[ -d "$MLX_SWIFT_DIR" ]] ||
    die "fixed mlx-swift checkout was not created: $MLX_SWIFT_DIR"
  [[ -d "$KERNELS_DIR" ]] ||
    die "missing MLX Metal kernel sources: $KERNELS_DIR"

  actual_revision="$(git -C "$MLX_SWIFT_DIR" rev-parse HEAD)"
  [[ "$actual_revision" == "$MLX_SWIFT_REVISION" ]] ||
    die "mlx-swift revision mismatch: expected $MLX_SWIFT_REVISION, found $actual_revision"

  expected_sources="$(expected_metal_source_list)"
  actual_sources="$(
    find "$KERNELS_DIR" -type f -name '*.metal' ! -name '*_nax.metal' |
      sed "s|^$KERNELS_DIR/||" |
      LC_ALL=C sort
  )"

  if [[ "$actual_sources" != "$expected_sources" ]]; then
    printf 'error: MLX Metal source set differs from the fixed 32-file contract\n' >&2
    printf '%s\n' '--- expected source list ---' >&2
    printf '%s\n' "$expected_sources" >&2
    printf '%s\n' '--- actual source list ---' >&2
    printf '%s\n' "$actual_sources" >&2
    die "Metal source selection stopped"
  fi

  while IFS= read -r source; do
    [[ -n "$source" ]] || continue
    metal_sources+=("$source")
  done < <(
    find "$KERNELS_DIR" -type f -name '*.metal' ! -name '*_nax.metal' |
      LC_ALL=C sort
  )

  [[ "${#metal_sources[@]}" -eq 32 ]] ||
    die "expected 32 Metal sources, found ${#metal_sources[@]}"

  verify_metal_toolchain
  mkdir -p "$STAGING_DIR/air"

  printf 'compiling 32 fixed MLX Metal sources\n'
  for source in "${metal_sources[@]}"; do
    relative_source="${source#"$KERNELS_DIR/"}"
    key="$(printf '%s' "$relative_source" | shasum -a 256 | awk '{print $1}' | cut -c1-16)"
    output_air="$STAGING_DIR/air/$key.air"

    if ! xcrun -sdk macosx metal \
      "${metal_flags[@]}" \
      -c "$source" \
      -I"$KERNELS_DIR" \
      -I"$MLX_SWIFT_DIR/Source/Cmlx/mlx" \
      -o "$output_air" \
      2>"$compiler_error"; then
      if grep -q "missing Metal Toolchain" "$compiler_error" 2>/dev/null; then
        printf 'error: missing Metal Toolchain\n' >&2
        printf 'run: xcodebuild -downloadComponent MetalToolchain\n' >&2
      fi
      sed -n '1,240p' "$compiler_error" >&2
      die "Metal compilation failed for $relative_source"
    fi

    air_files+=("$output_air")
  done

  xcrun -sdk macosx metallib "${air_files[@]}" -o "$output_metallib"

  if ! asset_matches "$output_metallib" "$METAL_BYTES" "$METAL_SHA256"; then
    show_asset_mismatch "$output_metallib" "$METAL_BYTES" "$METAL_SHA256"
    die "generated mlx.metallib did not match the fixed build provenance"
  fi

  mkdir -p "$METAL_DIR"
  mv -f "$output_metallib" "$METAL_PATH"
  printf 'installed atomically: %s\n' "$METAL_PATH"
}

verify_all_assets() {
  verify_asset_or_die "$WEIGHTS_PATH" "$WEIGHTS_BYTES" "$WEIGHTS_SHA256"
  verify_asset_or_die "$CONFIG_PATH" "$CONFIG_BYTES" "$CONFIG_SHA256"
  verify_model_config_contract
  verify_asset_or_die "$METAL_PATH" "$METAL_BYTES" "$METAL_SHA256"
}

verify_model_config_contract() {
  verify_manifest_value_for_file "$CONFIG_PATH" "model_name" "htdemucs"
  verify_manifest_value_for_file "$CONFIG_PATH" "model_class" "BagOfModelsMLX"
  verify_manifest_value_for_file "$CONFIG_PATH" "num_models" "1"
  verify_manifest_value_for_file "$CONFIG_PATH" "sub_model_class" "HTDemucsMLX"
  verify_manifest_value_for_file "$CONFIG_PATH" "kwargs.samplerate" "44100"
  verify_manifest_value_for_file "$CONFIG_PATH" "kwargs.audio_channels" "2"
  verify_manifest_value_for_file "$CONFIG_PATH" "kwargs.segment" "39/5"
  verify_array_count_for_file "$CONFIG_PATH" "kwargs.sources" "4"
  verify_manifest_value_for_file "$CONFIG_PATH" "kwargs.sources.0" "drums"
  verify_manifest_value_for_file "$CONFIG_PATH" "kwargs.sources.1" "bass"
  verify_manifest_value_for_file "$CONFIG_PATH" "kwargs.sources.2" "other"
  verify_manifest_value_for_file "$CONFIG_PATH" "kwargs.sources.3" "vocals"
}

verify_packaging_assets() {
  verify_asset_or_die "$METAL_PATH" "$METAL_BYTES" "$METAL_SHA256"
}

MODE="prepare"
case "${1:-}" in
  "")
    ;;
  --prepare-packaging)
    MODE="prepare-packaging"
    ;;
  --verify-only)
    MODE="verify"
    ;;
  --verify-packaging)
    MODE="verify-packaging"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_RESOLVED_PATH="$ROOT_DIR/Package.resolved"
ASSET_ROOT="$ROOT_DIR/Sources/VelouraLucent/Resources/StemModels"
MANIFEST_PATH="$ASSET_ROOT/stem-model-manifest.json"
NOTICE_ROOT="$ROOT_DIR/Sources/VelouraLucent/Resources/ThirdPartyNotices"
NOTICE_MANIFEST_PATH="$NOTICE_ROOT/third-party-notices-manifest.json"
VENDORED_DEMUCS_DIR="$ROOT_DIR/Vendor/demucs-mlx-swift"
MODEL_DIR="$ROOT_DIR/.stem-model-cache/htdemucs"
METAL_DIR="$ASSET_ROOT/MLX"

MODEL_REPO="mlx-community/demucs-mlx"
MODEL_REVISION="d4519e24ddc2dd4a11d56a193092433d852c3961"
MODEL_BASE_URL="https://huggingface.co/$MODEL_REPO/resolve/$MODEL_REVISION"

WEIGHTS_PATH="$MODEL_DIR/htdemucs.safetensors"
WEIGHTS_BYTES="168005865"
WEIGHTS_SHA256="339d267a7a6983a11eedbdc00413c602a65e9b9103f695fb5c2b2a481cd9d297"

CONFIG_PATH="$MODEL_DIR/htdemucs_config.json"
CONFIG_BYTES="1892"
CONFIG_SHA256="9258499513944fc062fbca0f11be425a446ec5702869a87e225323d7a57d2a01"

METAL_PATH="$METAL_DIR/mlx.metallib"
METAL_BYTES="106957102"
METAL_SHA256="82be53f327e9a39cb19a18272187187b7636f31989c44ad7ff474f7fe8171974"

MLX_SWIFT_DIR="$ROOT_DIR/.build/checkouts/mlx-swift"
MLX_SWIFT_REVISION="6ba4827fb82c97d012eec9ab4b2de21f85c3b33d"
KERNELS_DIR="$MLX_SWIFT_DIR/Source/Cmlx/mlx/mlx/backend/metal/kernels"

require_command shasum
require_command stat
[[ -f "$MANIFEST_PATH" ]] || die "missing tracked manifest: $MANIFEST_PATH"
verify_manifest_contract
verify_package_resolved_contract
verify_vendored_demucs_contract
verify_third_party_notices

if [[ "$MODE" == "verify" ]]; then
  verify_all_assets
  printf 'Stem Mode developer assets match schemaVersion 2 manifest values.\n'
  exit 0
fi

if [[ "$MODE" == "verify-packaging" ]]; then
  verify_packaging_assets
  printf 'Stem Mode bundled runtime assets match schemaVersion 2 manifest values.\n'
  exit 0
fi

mkdir -p "$ROOT_DIR/.build"
STAGING_DIR="$(mktemp -d "$ROOT_DIR/.build/stem-model-prepare.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

if [[ "$MODE" == "prepare-packaging" ]]; then
  prepare_metal_library
  verify_packaging_assets
  printf 'Stem Mode bundled runtime and notices are ready without AI model acquisition.\n'
  exit 0
fi

prepare_downloaded_models
prepare_metal_library
verify_all_assets

printf 'Stem Mode developer model cache and bundled runtime are ready.\n'
