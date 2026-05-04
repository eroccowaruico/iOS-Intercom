# Codec package 設定値

## 目的

本書は RideIntercom App が `Codec` package へ渡す設定値を定義する。

画面から直接設定する値は `docs/spec/App/setting parameters/App/設定値一覧.md` を正とし、本書では固定値、導出値、package adapter が決める値だけを扱う。

## Codec 設定

| package 設定 | App から渡す値 | 種別 |
|---|---|---|
| `CodecEncodingConfiguration.codec` | RTC の codec policy から導出する。画面設定としては持たない | adapter 導出 |
| `CodecEncodingConfiguration.format` | App の capture / packet audio adapter 境界で生成する | adapter 導出 |
| `AACELDv2Options` | package default | 固定 |
| `OpusOptions` | package default | 固定 |

送信 codec、HE-AAC 品質、Opus bitrate は画面設定として提供しない。codec 選択が必要になった場合は、App 設定ではなく RTC の codec policy として追加する。

## App 画面に出さない値

| 値 | 扱い |
|---|---|
| `preferredTransmitCodec` | App 設定としては持たない |
| `heAACv2Quality` | App 設定としては持たない |
| codec availability / fallback | Codec / RTC adapter で扱う |
| payload envelope 詳細 | package 仕様を正とする |

詳細な codec、payload、availability の仕様は `docs/spec/packages/Audio/Codec.md` を正とする。
