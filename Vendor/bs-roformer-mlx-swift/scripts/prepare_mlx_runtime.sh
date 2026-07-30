#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
  echo "usage: scripts/prepare_mlx_runtime.sh [debug|release]" >&2
  exit 2
fi

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_root="$(cd "$package_root/../.." && pwd)"
source_metallib="$project_root/Sources/VelouraLucent/Resources/StemModels/MLX/mlx.metallib"

if [[ ! -f "$source_metallib" ]]; then
  echo "error: MLX runtime asset not found: $source_metallib" >&2
  exit 1
fi

output_directory="$package_root/.build/$configuration"
if [[ ! -d "$output_directory" ]]; then
  output_directory="$(find "$package_root/.build" -maxdepth 3 -type d -path "*/$configuration" | head -n 1 || true)"
fi
if [[ -z "$output_directory" || ! -d "$output_directory" ]]; then
  echo "error: run 'swift build -c $configuration' first" >&2
  exit 1
fi

cp "$source_metallib" "$output_directory/mlx.metallib"
echo "prepared: $output_directory/mlx.metallib"
