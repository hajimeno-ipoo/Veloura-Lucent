# Stem Mode Third-Party Source Files

This directory preserves upstream license, acknowledgment, and model-card files
without rewriting their terms. It is a technical inventory, not a legal
interpretation.

`third-party-notices-manifest.json` fixes the relative path, byte count, and
SHA-256 of all 18 upstream files. `script/prepare_stem_models.sh --verify-only`
validates that manifest together with the three Stem Mode runtime assets.

The runtime dependency closure is fixed by `StemModels/stem-model-manifest.json`:

| Component | Fixed source | Preserved files |
|---|---|---|
| Demucs model metadata | `mlx-community/demucs-mlx@d4519e24ddc2dd4a11d56a193092433d852c3961` | `mlx-community-demucs-mlx/MODEL_CARD.md` |
| Original Demucs | `adefossez/demucs@eeac1d15891af95b1288d2884b95baa3e5baa96c` | `demucs/LICENSE` |
| demucs-mlx-swift | `c81c47178828db2d8bc66e64f80c745c64abdc94` | `demucs-mlx-swift/LICENSE` |
| mlx-swift | `0.30.6`, `6ba4827fb82c97d012eec9ab4b2de21f85c3b33d` | `mlx-swift/LICENSE`, `mlx-swift/ACKNOWLEDGMENTS.md` |
| Vendored MLX | mlx-swift fixed checkout | `mlx/LICENSE`, `mlx/ACKNOWLEDGMENTS.md` |
| Vendored mlx-c | mlx-swift fixed checkout | `mlx-c/LICENSE`, `mlx-c/ACKNOWLEDGMENTS.md` |
| Vendored fmt | mlx-swift fixed checkout | `fmt/LICENSE` |
| Vendored nlohmann/json | mlx-swift fixed checkout | `nlohmann-json/LICENSE.MIT` |
| Vendored metal-cpp | mlx-swift fixed checkout | `metal-cpp/LICENSE.txt` |
| swift-transformers | `1.1.6`, `573e5c9036c2f136b3a8a071da8e8907322403d0` | `swift-transformers/LICENSE` |
| swift-jinja | `2.3.2`, `f731f03bf746481d4fda07f817c3774390c4d5b9` | `swift-jinja/LICENSE` |
| swift-collections | `1.4.0`, `8d9834a6189db730f6264db7556a7ffb751e99ee` | `swift-collections/LICENSE.txt` |
| swift-argument-parser | `1.8.2`, `6a52f3251125d74daf04fcbd5e6f08a75d074382` | `swift-argument-parser/LICENSE.txt` |
| swift-numerics | `1.1.1`, `0c0290ff6b24942dadb83a929ffaaa1481df04a2` | `swift-numerics/LICENSE.txt` |
