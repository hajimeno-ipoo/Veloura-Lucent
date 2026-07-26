# Stem Model and Runtime Assets

The signed application manifest separates two downloadable AI model files from
the MLX runtime asset that ships inside the app.

## Downloadable after explicit user confirmation

The app downloads these files only from the full Hugging Face revision recorded
in `stem-model-manifest.json`:

```text
htdemucs/htdemucs.safetensors
htdemucs/htdemucs_config.json
```

They are not SwiftPM resources and must not be present in a distributed app.
The app stages both files under Application Support, validates the fixed source
revision contract, exact byte counts, SHA-256 values, and model configuration,
then activates the pair as one versioned installation. A failed, cancelled, or
invalid replacement must not remove the previously validated installation.

Every initial download, repair download, and complete re-download requires an
explicit user confirmation before any network request starts. The stable URLs
contain the complete 40-character revision. Redirect targets are temporary and
must not be stored as the asset source of record.

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

The model card, upstream MIT notice, runtime licenses, acknowledgements, and
the fixed notice inventory are tracked under `Resources/ThirdPartyNotices`.
