# RTC package 設定値

## 目的

本書は RideIntercom App が `RTC` package へ渡す設定値を定義する。

画面から直接設定する値は `docs/spec/App/setting parameters/App/設定値一覧.md` を正とし、本書では固定値、導出値、package adapter が決める値だけを扱う。

## CallRouteConfiguration

| package 設定 | App から渡す値 | 種別 |
|---|---|---|
| `enabledRoutes` | `[.multipeer]` | 固定 |
| `preferredRoute` | `.multipeer` | 固定 |
| `selectionMode` | `.singleRoute` | 固定 |
| `startsStandbyConnections` | package default | 固定 |
| `keepsPreviousRouteWarmDuringHandover` | package default | 固定 |

WebRTC は UI、credential、signaling 実装が揃うまで画面設定として提供しない。

## CallStartRequest / RTC 入力

| package 設定 | App から渡す値 | 種別 |
|---|---|---|
| `RTCCredential` | group ID と Keychain の group secret から生成する | App 状態から導出 |
| `PeerDescriptor` | local member ID と display name から生成する | App 状態から導出 |
| `AudioFormatDescriptor` | App の capture / packet audio adapter 境界で生成する | adapter 導出 |
| `AudioCodecConfiguration` | Codec / RTC policy から生成する | adapter 導出 |

group secret は group list へ保存せず、Keychain から取得して credential 生成にだけ使う。

## ApplicationDataMessage

| package 設定 | App から渡す値 | 種別 |
|---|---|---|
| `namespace` | `rideintercom.peerMuteState` | 固定 |
| `delivery` | `.reliable` | 固定 |
| `payload` | `{ "isMuted": Bool }` | App 状態から導出 |

Application Data の namespace と payload schema は App が所有する。RTC package は payload の意味を解釈しない。

## App 画面に出さない値

| 値 | 扱い |
|---|---|
| route fallback / restore policy | WebRTC 有効化まで画面設定にしない |
| route quality threshold | package 仕様または route policy 側で扱う |
| packet audio jitter / lifetime | package 仕様を正とする |
| sequence / duplicate filter | package 仕様を正とする |
| handshake / 暗号化詳細 | package 仕様を正とする |

詳細な route、packet audio、WebRTC、handover の仕様は `docs/spec/packages/RTC.md` を正とする。
