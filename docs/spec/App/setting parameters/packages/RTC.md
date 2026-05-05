# RTC package 設定値

## 目的

本書は、作り直す RideIntercom App が `RTC` package へ渡す固定値、導出値、runtime event / metrics の扱いを定義する。

画面から直接設定する値は `docs/spec/App/setting parameters/App/設定値一覧.md` を正とし、本書では package adapter が決める値だけを扱う。

## CallRouteConfiguration

| package 設定 | App から渡す値 | 種別 | Diagnostics で確認する値 |
|---|---|---|---|
| `enabledRoutes` | 初期は `[.multipeer]`。Cloudflare signaling が揃ったら `[.multipeer, .internet]` | adapter policy | route capabilities |
| `preferredRoute` | `.multipeer` | 固定 | active / preferred route |
| `selectionMode` | WebRTC 未構成時は `.singleRoute`。WebRTC 構成済みなら `.automaticFallbackAndRestore` | adapter policy | selection mode / handover state |
| `startsStandbyConnections` | WebRTC 構成済みなら `true`、未構成なら `false` | adapter policy | standby route state |
| `keepsPreviousRouteWarmDuringHandover` | WebRTC 構成済みなら `true` | adapter policy | handover state |

WebRTC の credential、Cloudflare signaling、native adapter が揃うまでは UI から route を選ばせない。App は package が返す route availability と failure reason を Diagnostics に表示する。

## CallStartRequest / RTC 入力

| package 設定 | App から渡す値 | 種別 | Diagnostics で確認する値 |
|---|---|---|---|
| `RTCCredential` | group ID と Keychain の group secret から生成する | App 状態から導出 | credential presence のみ |
| `PeerDescriptor` | local member ID と display name から生成する | App 状態から導出 | peer ID hash / display name |
| `expectedPeers` | selected group の保存 member から生成する | App 状態から導出 | expected / connected / authenticated count |
| `AudioFormatDescriptor` | `16_000` / mono / Float PCM を packet audio 用に変換する | adapter 導出 | audio format |
| `AudioCodecConfiguration.preferredCodecs` | `preferredTransmitCodec` を先頭に置き、残り候補と `.pcm16` fallback を続ける | 画面設定から導出 | requested / selected codec |
| `PacketAudioReceiveConfiguration` | package default | 固定 | playout delay / queue / drop metrics |

group secret は group list へ保存せず、Keychain から取得して credential 生成にだけ使う。ログと Diagnostics には secret、token、認証 MAC、鍵材料を出さない。

## ApplicationDataMessage

| package 設定 | App から渡す値 | 種別 |
|---|---|---|
| `namespace` | `rideintercom.peerMuteState` | 固定 |
| `delivery` | `.reliable` | 固定 |
| `payload` | `{ "isMuted": Bool }` | App 状態から導出 |

Application Data の namespace と payload schema は App が所有する。RTC package は payload の意味を解釈しない。

## Runtime event / metrics の App 側処理

| Event / metrics | App の扱い | UI 反映 | ログ |
|---|---|---|---|
| connection state | Call 表示用の connection summary へ要約 | Call / Diagnostics | `rtc.connection.started`、`rtc.connection.failed` |
| route state | active / standby / unavailable を保持 | Diagnostics の Route 行 | `rtc.route.changed` |
| handover | media 所有と出力を同期 | Call / Diagnostics | `rtc.route.handover.started`、`rtc.route.handover.completed` |
| member update | participant 表示へ反映 | Call Participants | debug |
| `RouteMetrics` | RTT、jitter、packet loss、queue、drop を要約 | Diagnostics の Quality 行 | warning threshold 超過時だけ |
| received audio frame | app-managed packet audio の decode へ渡す | 参加者 level / Reception | 高頻度通常ログは禁止 |
| application data | namespace ごとに App が decode | participant mute state | decode 失敗のみ debug |
| error | 復旧可能性で分類する | Call エラー / Diagnostics | warning / error |

## App 画面に出さない値

| 値 | 扱い |
|---|---|
| route fallback / restore policy | adapter policy として扱い、通常 UI では切り替えない |
| route quality threshold | package 仕様または adapter policy 側で扱う |
| packet audio jitter / lifetime | package default と metrics を正とする |
| sequence / duplicate filter | package 仕様を正とする |
| handshake / 暗号化詳細 | package 仕様を正とし、App は結果だけを扱う |
| WebRTC native 型 | App API と UI へ露出しない |

詳細な route、packet audio、WebRTC、handover の仕様は `docs/spec/packages/RTC.md` を正とする。
