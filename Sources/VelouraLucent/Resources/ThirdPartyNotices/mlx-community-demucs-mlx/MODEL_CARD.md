---
license: mit
library_name: mlx
tags:
  - mlx
  - audio
  - music-source-separation
  - source-separation
  - demucs
  - htdemucs
  - hdemucs
  - apple-silicon
base_model: adefossez/demucs
pipeline_tag: audio-to-audio
---

> Originally from: [iky1e/demucs-mlx](https://huggingface.co/iky1e/demucs-mlx)
> 
> Float16 variant: [mlx-community/demucs-mlx-fp16](https://huggingface.co/mlx-community/demucs-mlx-fp16)

# Demucs — MLX

MLX-compatible weights for all 8 pretrained [Demucs](https://github.com/adefossez/demucs) models, converted to `safetensors` format for inference on Apple Silicon.

Demucs is a music source separation model that splits audio into stems: `drums`, `bass`, `other`, `vocals` (and `guitar`, `piano` for 6-source models).

## Models

| Model | What it is | Architecture | Sub-models | Sources | Weights | Tensors |
|-------|-----------|-------------|-----------|---------|---------|---------|
| `htdemucs` | Default v4 model, best speed/quality balance | HTDemucs (v4) | 1 | 4 | 160 MB | 573 |
| `htdemucs_ft` | Fine-tuned v4, best overall quality | HTDemucs (v4) | 4 (fine-tuned) | 4 | 641 MB | 2292 |
| `htdemucs_6s` | 6-source v4 (adds guitar + piano stems) | HTDemucs (v4) | 1 | 6 | 105 MB | 565 |
| `hdemucs_mmi` | v3 hybrid, trained on more data | HDemucs (v3) | 1 | 4 | 319 MB | 379 |
| `mdx` | v3 bag-of-models ensemble | Demucs + HDemucs | 4 (bag) | 4 | 1.3 GB | 1298 |
| `mdx_extra` | v3 ensemble trained on extra data | HDemucs | 4 (bag) | 4 | 1.2 GB | 1516 |
| `mdx_q` | Quantized v3 ensemble (same quality, smaller) | Demucs + HDemucs | 4 (bag) | 4 | 1.3 GB | 1298 |
| `mdx_extra_q` | Quantized v3 extra ensemble | HDemucs | 4 (bag) | 4 | 1.2 GB | 1516 |

All models output stereo audio at 44.1 kHz.

## Origin

- Original model/repo: [adefossez/demucs](https://github.com/adefossez/demucs)
- License: MIT (same as original Demucs)
- Conversion path: PyTorch checkpoints → safetensors + JSON config (direct, no intermediary)
- Swift MLX port: [iky1e/demucs-mlx-swift](https://github.com/iky1e/demucs-mlx-swift)

No fine-tuning or quantization was applied — these are direct conversions of the original pretrained weights.

## Files

Each model consists of two files at the repo root:

- `{model_name}.safetensors` — model weights (float32)
- `{model_name}_config.json` — model class, architecture config, and bag-of-models metadata

## Usage

### Swift (demucs-mlx-swift)

Models are downloaded automatically from this repo. No manual setup required.

```bash
# Separate a song into stems
demucs-mlx-swift -n htdemucs song.wav

# Use a specific model
demucs-mlx-swift -n htdemucs_ft song.wav

# Two-stem mode (vocals + instrumental)
demucs-mlx-swift -n htdemucs --two-stems vocals song.wav
```

Or use the Swift API directly:

```swift
import DemucsMLX

let separator = try DemucsSeparator(modelName: "htdemucs")
let result = try separator.separate(fileAt: URL(fileURLWithPath: "song.wav"))
```

### Python (demucs-mlx)

```bash
pip install demucs-mlx
demucs-mlx -n htdemucs song.wav
```

## Converting from PyTorch

To reproduce the export directly from PyTorch Demucs checkpoints:

```bash
pip install demucs safetensors numpy

# Export all 8 models
python export_from_pytorch.py --out-dir ./output

# Export specific models
python export_from_pytorch.py --models htdemucs htdemucs_ft --out-dir ./output
```

The conversion script (`export_from_pytorch.py`) is available in the [demucs-mlx-swift](https://github.com/iky1e/demucs-mlx-swift) repo under `scripts/`.

## Citation

```bibtex
@inproceedings{rouard2022hybrid,
  title={Hybrid Transformers for Music Source Separation},
  author={Rouard, Simon and Massa, Francisco and Defossez, Alexandre},
  booktitle={ICASSP 23},
  year={2023}
}

@inproceedings{defossez2021hybrid,
  title={Hybrid Spectrogram and Waveform Source Separation},
  author={Defossez, Alexandre},
  booktitle={Proceedings of the ISMIR 2021 Workshop on Music Source Separation},
  year={2021}
}
```
