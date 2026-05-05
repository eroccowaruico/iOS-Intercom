# AudioMixer package 設定値

## 目的

本書は RideIntercom App が `AudioMixer` package へ渡す設定値を定義する。

画面から直接設定する値は `docs/spec/App/setting parameters/App/設定値一覧.md` を正とし、本書では固定値、導出値、package adapter が決める値だけを扱う。

## Mixer 設定

| package 設定 | App から渡す値 | 種別 |
|---|---|---|
| format | package default、または capture / output adapter が要求する format | adapter 導出 |
| TX bus effect chain | ordered effect stage 配列。初期構成は SoundIsolation、VADGate、DynamicsProcessor、PeakLimiter | adapter 導出 |
| RX peer bus effect chain | peer 単位の ordered effect stage 配列。初期構成は必要に応じた SoundIsolation | adapter 導出 |
| RX master bus effect chain | 受信全体の ordered effect stage 配列。初期構成は必要に応じた SoundIsolation | adapter 導出 |
| master bus volume | `isOutputMuted ? 0 : masterOutputVolume` | 画面設定から導出 |
| peer bus volume | `remoteOutputVolumes[peerID]`。未設定 peer は `1.0` | 画面設定から導出 |

受信側は peer ごとに RX peer bus を作り、全 RX peer bus を receive master bus へ route して mix down する。相手が複数いる場合は peer bus も複数になり、master bus は mix 後の 1 本だけを表す。

TX bus、RX peer bus、RX master bus の effect chain は App adapter が順序を決める。Diagnostics は同じ stage 配列を表示し、effect 追加時に UI 構造を変更しない。

## App 画面に出さない値

| 値 | 扱い |
|---|---|
| default format | package 仕様を正とする |
| bus ID / routing | App adapter の固定構成として扱う |
| effect chain 再構築 | package adapter が扱い、画面設定にしない |
| effect index | package adapter が扱い、画面設定にしない |
| soft clip / limiter の内部値 | Effectors 側の設定に寄せる |

詳細な bus、format、routing の仕様は `docs/spec/packages/Audio/Mixer.md` を正とする。
