# VADGate package 設定値

## 目的

本書は RideIntercom App が `VADGate` package へ渡す設定値を定義する。

画面から直接設定する値は `docs/spec/App/setting parameters/App/設定値一覧.md` を正とし、本書では固定値、導出値、package adapter が決める値だけを扱う。

## VADGateConfiguration

| package 設定 | App から渡す値 | 種別 |
|---|---|---|
| `VADGateConfiguration` | package default、または `voiceActivityDetectionThreshold` から導出した App preset | 画面設定から導出 |
| attack / release | package default | 固定 |
| noise floor | package default | 固定 |
| gate gain / ramp | package default | 固定 |

`voiceActivityDetectionThreshold` は App 画面から設定するが、package の細かい VAD parameter を画面へ直接出さない。

## App 画面に出さない値

| 値 | 扱い |
|---|---|
| attack duration | package default |
| release duration / hangover | package default |
| noise floor adaptation | package default |
| speech / silence gain | package default |
| gain ramp | package default |

詳細な VAD / gate の仕様は `docs/spec/packages/Audio/Effectors/VADGate.md` を正とする。
