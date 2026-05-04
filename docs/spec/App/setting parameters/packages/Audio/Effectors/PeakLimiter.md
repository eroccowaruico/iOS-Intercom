# PeakLimiter package 設定値

## 目的

本書は RideIntercom App が `PeakLimiter` package へ渡す設定値を定義する。

画面から直接設定する値は `docs/spec/App/setting parameters/App/設定値一覧.md` を正とし、本書では固定値、導出値、package adapter が決める値だけを扱う。

## PeakLimiterConfiguration

| package 設定 | App から渡す値 | 種別 |
|---|---|---|
| `PeakLimiterConfiguration` | package default | 固定 |
| effect chain 挿入 | App adapter の固定構成で決める | adapter 導出 |

PeakLimiter の attack、decay、pre-gain などは画面設定として提供しない。

## App 画面に出さない値

| 値 | 扱い |
|---|---|
| attack time | package default |
| decay time | package default |
| pre-gain | package default |
| Audio Unit parameter | package 仕様を正とする |

詳細な PeakLimiter の仕様は `docs/spec/packages/Audio/Effectors/PeakLimiter.md` を正とする。
