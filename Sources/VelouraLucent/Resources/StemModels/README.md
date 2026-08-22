# Stem Model and Runtime Assets

The signed application manifests separate each model's two downloadable AI
model files from the MLX runtime asset that ships inside the app.

## Downloadable after an explicit user action

The app downloads the selected model only from the full Hugging Face revision
recorded in its manifest:

```text
stem-model-manifest.json
htdemucs/htdemucs.safetensors
htdemucs/htdemucs_config.json

bs-roformer-sw-manifest.json
bs-roformer-sw/bs_roformer_sw.safetensors
bs-roformer-sw/bs_roformer_sw_config.json
```

They are not SwiftPM resources and must not be present in a distributed app.
The app stages both files under Application Support, validates the fixed source
revision contract, exact byte counts, SHA-256 values, and model configuration,
then activates the pair as one versioned installation. HTDemucs and
BS-RoFormer-SW keep independent active pointers, so installing or repairing one
does not replace the other. A failed, cancelled, or invalid replacement must
not remove the previously validated installation.

## Runtime output contracts

- HTDemucs keeps its four independent outputs: `drums / bass / other / vocals`.
- BS-RoFormer-SW keeps its six independent outputs: `bass / drums / other /
  vocals / guitar / piano`.
- The app validates the selected model's output names, count, active roles, and
  pure-sum order before processing. BS-RoFormer-SW does not merge guitar or
  piano into other, and neither model falls back to the other model's contract.

Every initial download, repair download, and complete re-download starts only
from the corresponding action in the Stem separation section. Distribution
details are shown in the app's About window, while the root-owned progress
sheet shows file names, destination, byte progress, cancellation, and errors.
The stable URLs contain the complete 40-character revision. Redirect targets
are temporary and must not be stored as the asset source of record.

## Bundled MLX runtime

```text
StemModels/MLX/mlx.metallib
```

`mlx.metallib` is built from the fixed `mlx-swift 0.30.6` checkout, validated,
placed at `mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib`, and signed
as part of the application. It is not part of model download or re-download.

Prepare developer model copies and the bundled Metal library:

```bash
script/prepare_stem_models.sh
```

Verify all developer assets without downloading or compiling:

```bash
script/prepare_stem_models.sh --verify-only
```

Verify only the files required to build and sign the application:

```bash
script/prepare_stem_models.sh --verify-packaging
```

The HTDemucs model card, upstream MIT notice, BS-RoFormer-SW project model
notice, runtime licenses, acknowledgements, and the fixed notice inventory are
tracked under `Resources/ThirdPartyNotices`.
