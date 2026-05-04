# SessionManager package 設定値

## 目的

本書は RideIntercom App が `SessionManager` package へ渡す設定値を定義する。

画面から直接設定する値は `docs/spec/App/setting parameters/App/設定値一覧.md` を正とし、本書では固定値、導出値、package adapter が決める値だけを扱う。

## AudioSessionConfiguration

| package 設定 | App から渡す値 | 種別 |
|---|---|---|
| `mode` | `.default` | 固定 |
| `defaultToSpeaker` | `selectedOutputPort` が built-in speaker のとき `true` | 画面設定から導出 |
| `prefersEchoCancelledInput` | `false` | 固定 |
| `preferredInput` | `selectedInputPort` から package 型へ変換 | 画面設定から導出 |
| `preferredOutput` | `selectedOutputPort` から package 型へ変換 | 画面設定から導出 |

`voiceChat` と echo cancellation は、画面設定として提供するまでは有効化しない。

## AudioInputVoiceProcessingConfiguration

| package 設定 | App から渡す値 | 種別 |
|---|---|---|
| `soundIsolationEnabled` | `isSoundIsolationEnabled` | 画面設定から導出 |
| `otherAudioDuckingEnabled` | `isDuckOthersEnabled && isOtherAudioDuckingActive` | 画面設定と再生状態から導出 |
| `duckingLevel` | `isOtherAudioDuckingActive` のとき `.normal`、それ以外は `.minimum` | 導出 |
| `inputMuted` | `isMuted` | 画面設定から導出 |

`isOtherAudioDuckingActive` は次をすべて満たす場合だけ `true` とする。

| 条件 |
|---|
| `isDuckOthersEnabled == true` |
| Audio Check 中ではない |
| 直近に可聴な受信音声を最終出力へ渡している |
| `isOutputMuted == false` |
| `masterOutputVolume > 0` |
| 該当 peer の出力音量が 0 ではない |

## App 画面に出さない値

| 値 | 扱い |
|---|---|
| iOS category / mode / options | package 仕様を正とし、App 画面では個別設定しない |
| CoreAudio device 切替の詳細 | package adapter に閉じ込める |
| advanced ducking の OS API 詳細 | package 仕様を正とし、App 画面では扱わない |
| voice processing bypass | `soundIsolationEnabled` と `otherAudioDuckingEnabled` から導出する |

詳細な OS 差分と内部既定値は `docs/spec/packages/Audio/SessionManager.md` を正とする。
