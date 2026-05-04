# AudioMixer package 設定値

## 目的

本書は RideIntercom App が `AudioMixer` package へ渡す設定値を定義する。

画面から直接設定する値は `docs/spec/App/setting parameters/App/設定値一覧.md` を正とし、本書では固定値、導出値、package adapter が決める値だけを扱う。

## Mixer 設定

| package 設定 | App から渡す値 | 種別 |
|---|---|---|
| format | package default、または capture / output adapter が要求する format | adapter 導出 |
| master bus volume | `isOutputMuted ? 0 : masterOutputVolume` | 画面設定から導出 |
| peer bus volume | `remoteOutputVolumes[peerID]`。未設定 peer は `1.0` | 画面設定から導出 |

## App 画面に出さない値

| 値 | 扱い |
|---|---|
| default format | package 仕様を正とする |
| bus ID / routing | App adapter の固定構成として扱う |
| effect chain 再構築 | package adapter が扱い、画面設定にしない |
| effect index | package adapter が扱い、画面設定にしない |
| soft clip / limiter の内部値 | Effectors 側の設定に寄せる |

詳細な bus、format、routing の仕様は `docs/spec/packages/Audio/Mixer.md` を正とする。
