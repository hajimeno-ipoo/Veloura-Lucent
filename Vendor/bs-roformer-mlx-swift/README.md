# bs-roformer-mlx-swift

Veloura LucentでBS-RoFormer-SWをローカル実行するための、単独MLX Swiftランタイムです。
対象は確認済みの6ステムモデル1つだけです。モデル取得、モデル選択UI、自動フォールバック、
通常モード、Stem解析以降の処理は含みません。

## 実行

```bash
swift build -c release
./scripts/prepare_mlx_runtime.sh release

.build/release/bs-roformer-mlx-swift \
  /path/to/BS-Roformer-SW.safetensors \
  Config/BS-Roformer-SW.json \
  /path/to/input.wav \
  /path/to/output
```

入力は44.1kHz・ステレオです。出力順は
`bass, drums, other, vocals, guitar, piano`です。

## 検証

```bash
swift test

python scripts/compare_python_outputs.py \
  /path/to/swift-output \
  /path/to/python-output \
  --python-prefix "000_"
```

Swift側はアプリと同じMLX Swift 0.30.6へ固定しています。モデルファイルはリポジトリへ
同梱しません。
