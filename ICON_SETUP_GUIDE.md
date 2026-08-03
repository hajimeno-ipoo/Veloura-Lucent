# Veloura Lucent アイコン設定メモ

## 結論

- 主アイコンは `Resources/VelouraLucent.icon` です。
- `Resources/IconLayers/*.svg` は、Figmaで作成した編集可能なレイヤー素材です。
- `AppIcon-1024.png` は、Xcode直起動、About画面、既存Asset Catalogの互換用画像です。
- 配布用の `.app` は、ビルド時に `.icon` のDefault表示を `ictool` でPNG化し、互換用Asset Catalogも生成します。

AppleのIcon Composerは、背面から前面へ並べた複数レイヤーをLiquid Glassとしてレンダリングし、`.icon`をXcodeへ追加して利用する方式です。素材はSVGを優先し、マスクや影などの効果はIcon Composer側で設定します。

## アイコンの構成

```text
Figma
  Veloura Lucent Icon - Editable Layers
    -> 背景、縁、後方ウェーブ、交差ウェーブ、前方ウェーブ、ハイライト

リポジトリ
  Resources/IconLayers/*.svg
    -> Figmaから書き出した編集用・再利用用レイヤー
  Resources/VelouraLucent.icon
    -> icon.json + Assets/*.svg（背景はicon.jsonのfill、外周と2本のウェーブの3つのSVG）
  Resources/AppIcon-1024.png
  Sources/VelouraLucent/Resources/AppIcon-1024.png
    -> .iconのDefaultレンダリング済みPNG
```

## 配布用 `.app` の経路

`script/build_and_run.sh` は、次の順で処理します。

1. `Resources/VelouraLucent.icon` を `ictool` で macOS / Default の1024×1024 PNGへレンダリングします。
2. そのPNGから一時的な `Assets.xcassets/AppIcon.appiconset` を作成します。
3. `xcrun actool` で `Assets.car` を生成します。
4. `.icon`を `Contents/Resources/VelouraLucent.icon` として同梱します。
5. `Info.plist` の `CFBundleIconName` を `VelouraLucent` に設定します。
6. PNGも `Contents/Resources/AppIcon-1024.png` として同梱します。

`.icon`が存在する場合は、配布 `.app` の主アイコンを `.icon` にします。Asset CatalogとPNGは互換表示のために残します。

## Xcodeから直接起動する経路

`Package.swift` は次の2つをSwiftPMリソースとして登録します。

```swift
resources: [
    .process("Resources/AppIcon-1024.png"),
    .copy("Resources/VelouraLucent.icon")
]
```

Swift PackageをXcodeから直接実行した場合は、完全な `.app` バンドルにならないことがあります。そのため `VelouraLucentApp.swift` は、メインバンドルに `.icon` がない場合だけDefault PNGを `NSApp.applicationIconImage` に適用します。

## アイコンを変更する手順

1. Figmaの `Veloura Lucent Icon - Editable Layers` を更新します。
2. 各レイヤーを1024×1024のSVGとして書き出し、`Resources/IconLayers/`へ保存します。
3. 外周、後方のガラスウェーブ、前方のガラスウェーブの3つを
   `Resources/VelouraLucent.icon/Assets/`へ反映します。背景は`icon.json`の`fill`で管理し、
   `icon.json`のレイヤー順を確認します。
   Figmaの表示とIcon Composerの実レンダリングは合成方法が異なるため、形状を揃えた後に
   `ictool`のDefault出力を基準として、`.icon/Assets`の不透明度を微調整する場合があります。
4. `.icon`を検証します。

```bash
cd /path/to/compose-app-icon/scripts
uv run python validate_icon.py "/path/to/Veloura Lucent/Resources/VelouraLucent.icon"
```

5. Default表示を確認します。

```bash
IC_TOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
"$IC_TOOL" Resources/VelouraLucent.icon \
  --export-image \
  --output-file /tmp/veloura-icon-default.png \
  --platform macOS \
  --rendition Default \
  --width 1024 \
  --height 1024 \
  --scale 1
```

6. 必要なら、生成したDefault PNGを次の2か所へ反映します。

```text
Resources/AppIcon-1024.png
Sources/VelouraLucent/Resources/AppIcon-1024.png
```

7. Releaseビルドと起動確認を実行します。

```bash
./script/build_and_run.sh --verify
```

## 確認場所

- `.icon`の構文・Assets参照：Icon Composer skillの`compose-app-icon/scripts/`で`validate_icon.py`を実行
- Icon Composerの読み込み・レンダリング：`ictool ... --rendition Default`
- 配布アイコン：`dist/Veloura Lucent.app/Contents/Resources/VelouraLucent.icon`
- 互換画像：`dist/Veloura Lucent.app/Contents/Resources/AppIcon-1024.png`
- Info.plist：`dist/Veloura Lucent.app/Contents/Info.plist`
- SwiftPM直起動：XcodeからRunし、Dockのアイコンを確認

## 注意点

- `.icon`のレイヤーは背面から前面の順に並べます。
- Icon Composerが自動適用するマスク、影、透過、スペキュラの見た目を、素材SVGへ重ねて書き込まないようにします。
- `icon.json`のスキーマ検証が成功しても、Icon Composerの実装差で開けない場合があります。必ず `ictool` でもレンダリングします。
- Figmaの書き出しSVGに含まれる編集用の背景やキャンバスマスクは、Icon Composerへ渡す前に除去します。
- Figmaと`ictool`の見た目が異なる時は、形状を変えずに`.icon/Assets`の透明度を調整し、Default・Dark・Tintedの出力を再確認します。
