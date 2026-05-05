# RideIntercom Diagnostics 画面項目

## 目的

本書は Diagnostics タブの UI 項目を定義する。

Diagnostics はログを読む代替ではない。通話、音声、codec、route、認証、招待の現在状態を一覧カードで見せ、ぱっと見で今何が起きているか分かる画面にする。

## 画面構成

| 項目名（日本語） | 項目ID | 目的 | 実装 | 更新周期 | 表示仕様 |
|---|---|---|---|---|---|
| 診断画面 | `diagnostics-screen` | package runtime report と App 状態を要約する | `DiagnosticsView` | 0.5 秒 | `TimelineView` + `ScrollView` |
| 送信パイプライン | `diagnostics-live-pipeline` | ローカル送信がどこまで進んでいるかを読む | `LiveTransmitPipelineView` | 0.5 秒 | 上部に横並びまたは折り返し表示 |
| 受信パイプライン | `diagnostics-live-rx-pipeline` | 受信音声が出力までどこまで進んでいるかを読む | `LiveReceivePipelineView` | 0.5 秒 | 送信パイプラインと同じ横並びまたは折り返し表示 |
| 現在状態一覧 | `diagnostics-overview-grid` | 重要状態を一覧カードで見る | `DiagnosticsOverviewGrid` | 0.5 秒 | adaptive grid。各カードは 1 層だけを担当 |

## 送信パイプライン

| 項目名（日本語） | 親項目 | 項目ID | ラベル | データ仕様 | 表示仕様 | 状態・異常系の考え方 |
|---|---|---|---|---|---|---|
| SessionManager sessionステップ | `diagnostics-live-pipeline` | `pipeline-session-step` | Session | `AudioSessionSnapshot`, `audioSessionProfile`, 直近 session report | 状態アイコン + profile | session error は blocked |
| SessionManager inputステップ | `diagnostics-live-pipeline` | `pipeline-input-step` | Input | `AudioInputStreamCapture` snapshot、voice processing report、`isMuted` | stream format、frame count、mute | ミュートは故障ではなく waiting |
| AudioMixer TX busステップ | `diagnostics-live-pipeline` | `pipeline-mixer-step` | TX Bus | TX bus / source / routing 状態 | `Mic -> FX` として表示 | mixer 未開始は neutral |
| AudioMixer effect chainステップ | `diagnostics-live-pipeline` | `pipeline-effects-step` | FX Chain | ordered effect stage 配列 | stage 数と注目 stage を表示 | stage 内の unsupported / bypassed を warning 以下で表示 |
| codec ステップ | `diagnostics-live-pipeline` | `pipeline-codec-step` | Codec | `preferredTransmitCodec`, `selectedTransmitCodec` | requested と selected を表示。fallback 時は `requested -> selected / Fallback` | fallback は warning |
| RTC ステップ | `diagnostics-live-pipeline` | `pipeline-rtc-step` | RTC | `sentVoicePacketCount`, route, media ownership | packet 送信数と route | 送信 0 は未発話または未接続として読む |

## 送信 effect chain 表示

effect chain は `AudioMixer` の TX bus 内部にある ordered stages として表示する。VADGate は独立した pipeline 層ではなく、effect chain の 2 つ目の stage として扱う。

| stage | accessibilityIdentifier | package | 表示する状態 |
|---|---|---|---|
| SoundIsolation | `pipeline-effect-stage-sound-isolation` | SoundIsolation | enabled / bypassed / unavailable |
| VADGate | `pipeline-effect-stage-vad-gate` | VADGate | speech / silent / muted、感度 preset、noise floor、threshold、gate gain |
| DynamicsProcessor | `pipeline-effect-stage-dynamics-processor` | DynamicsProcessor | leveling ready / idle |
| PeakLimiter | `pipeline-effect-stage-peak-limiter` | PeakLimiter | peak guard ready / idle |

| 拡張ルール | 仕様 |
|---|---|
| stage 追加 | effect chain の stage 配列に追加するだけで Diagnostics の表示順へ反映する |
| 固定文字列禁止 | `SoundIsolation -> VADGate -> DynamicsProcessor -> PeakLimiter` のような固定文言を UI の正本にしない |
| 一覧性 | stage が増えた場合は grid で折り返し、ログを読まなくても各 stage の現在状態を読めるようにする |

## 受信パイプライン

| 項目名（日本語） | 親項目 | 項目ID | ラベル | データ仕様 | 表示仕様 | 状態・異常系の考え方 |
|---|---|---|---|---|---|---|
| RTC受信ステップ | `diagnostics-live-rx-pipeline` | `receive-pipeline-rtc-step` | RTC RX | route、受信 packet count、media ownership | route と RX count | 受信 0 は未発話または未接続として読む |
| Codec decodeステップ | `diagnostics-live-rx-pipeline` | `receive-pipeline-codec-step` | Decode | selected codec、drop count | codec と drop を表示 | drop は warning |
| peer busステップ | `diagnostics-live-rx-pipeline` | `receive-pipeline-peer-bus-step` | Peer Buses | authenticated peer count、peer 別 RX / JIT / PLAY / level | bus 数と RX count。下段に peer bus 一覧を表示 | peer なしは neutral / waiting |
| peer effect chainステップ | `diagnostics-live-rx-pipeline` | `receive-pipeline-peer-effects-step` | Peer FX | peer effect stage 配列 | 各 peer bus に同じ ordered stage 配列を適用する前提で stage 数と注目 stage を表示 | stage 単位で unsupported / bypassed を表示 |
| receive mix downステップ | `diagnostics-live-rx-pipeline` | `receive-pipeline-mix-step` | Mix Down | peer bus count、受信 packet count | `n buses -> master` として複数 peer が master に集約されることを表示 | bus なしは waiting |
| receive master busステップ | `diagnostics-live-rx-pipeline` | `receive-pipeline-master-bus-step` | RX Master | played frame count、master volume、source bus count | source bus count と OUT volume。mix 後の 1 本の master bus として表示 | 再生 0 は waiting |
| master effect chainステップ | `diagnostics-live-rx-pipeline` | `receive-pipeline-master-effects-step` | Master FX | master effect stage 配列 | stage 数と注目 stage を表示 | stage 単位で unsupported / bypassed を表示 |
| outputステップ | `diagnostics-live-rx-pipeline` | `receive-pipeline-output-step` | Output | output renderer snapshot、mute、volume | stream format、frame count、mute | mute / volume 0 は warning |

## 受信 mix topology 表示

`LiveReceivePipelineView` は受信パイプラインの下に `receive-mix-topology` を表示する。ここでは peer bus が複数並び、最後に receive master bus へ mix down される構造をログなしで確認できるようにする。

| 項目 | accessibilityIdentifier | 表示する状態 |
|---|---|---|
| peer bus 空状態 | `receive-peer-buses-empty` | 認証済み peer bus がまだない |
| peer bus card | `receive-peer-bus-{index}` | peer 名、RX / JIT / PLAY、現在 level |
| master mix card | `receive-master-mix-card` | source bus count、総 RX、PLAY、master volume / mute、出力 level |

## 受信 effect chain 表示

受信側は peer bus と receive master bus のそれぞれに ordered stages を持つ。Diagnostics は chain ごとの stage 配列を表示する。

| chain | stage | accessibilityIdentifier | package | 表示する状態 |
|---|---|---|---|---|
| Peer FX | SoundIsolation | `receive-peer-effect-stage-sound-isolation` | SoundIsolation | enabled / bypassed / unavailable |
| Master FX | SoundIsolation | `receive-master-effect-stage-sound-isolation` | SoundIsolation | enabled / bypassed / unavailable |

| 拡張ルール | 仕様 |
|---|---|
| stage 追加 | peer または master の effect chain stage 配列に追加するだけで Diagnostics の表示順へ反映する |
| 固定文字列禁止 | 受信側も固定の effect 名列挙を UI の正本にしない |
| 一覧性 | peer chain と master chain を別々に表示し、どちらで処理が止まっているかをログなしで読めるようにする |

## 現在状態一覧

| 項目名（日本語） | 項目ID | ラベル | データ仕様 | 表示仕様 | severity |
|---|---|---|---|---|---|
| 通話カード | `diag-call-route-summary` | `Call` | `connectionLabel`, `routeLabel`, `isAudioReady` | `CALL {state}` / `{route} / MEDIA ...` | 接続中は ok、未接続は neutral |
| セッションカード | `diag-session-summary` | `Session` | `AudioSessionSnapshot`, 直近 session report | `SESSION ...` / `IN ... / OUT ...` | `audioErrorMessage` があれば error |
| 入力streamカード | `diag-input-stream-summary` | `Input Stream` | `AudioInputStreamCapture` snapshot、voice processing report | `INPUT ...` / `VAD ... / ISOLATION ... / DUCK ...` | muted は warning、未開始は neutral |
| 出力streamカード | `diag-output-stream-summary` | `Output Stream` | output renderer snapshot、schedule count | `OUTPUT ...` / playback summary | muted は warning、未開始は neutral |
| codecカード | `diag-codec-summary` | `Codec` | requested codec、selected codec、bitrate、fallback | `CODEC requested -> selected` / bitrate | fallback は warning |
| route metricsカード | `diag-route-metrics-summary` | `Route Metrics` | `RouteMetrics`、reception snapshot | RTT、jitter、loss、drop、queue | loss/drop は warning |
| mixerカード | `diag-mixer-summary` | `Mixer` | bus count、played frame count、master volume | `MIX BUS ...` / `OUT ...%` | volume 0 または mute は warning |
| 認証カード | `diag-auth-summary` | `Authentication` | connected / authenticated peer count | `AUTH ...` / `PEERS ...` | 認証済み peer ありなら ok |
| 招待カード | `diag-invite-summary` | `Invite` | invite URL、invite status、selected group | `INVITE ...` / group summary | 招待可能なら ok |

## 一覧性のルール

| 項目 | 仕様 |
|---|---|
| 表示粒度 | 1 カードは 1 つの層だけを示す。複数層の原因推測を 1 行へ詰め込まない |
| 文字量 | summary は 1 行、detail は補足。長文ログや stack trace は置かない |
| 色 | ok / warning / error / neutral をカード左アイコン色で示す |
| 表示順 | Call、Session、Input、Output、Codec、Route、Mixer、Authentication、Invite の順を維持する |
| ログとの関係 | Diagnostics で現在値を読み、ログは操作境界や失敗の後追い調査に使う |
| 環境差異 | unsupported / ignored は warning 以下に留め、継続可能な状態として表示する |

## Accessibility Identifier

既存 UI テストと調査導線を壊さないため、一覧カードは旧 debug label の identifier を維持する。

| カード | accessibilityIdentifier |
|---|---|
| Call | `realDeviceCallDebugSummaryLabel` |
| Session | `audioSessionSummaryLabel` |
| Input Stream | `audioInputProcessingSummaryLabel` |
| Output Stream | `playbackDebugSummaryLabel` |
| Codec | `codecDebugSummaryLabel` |
| Route Metrics | `receptionDebugSummaryLabel` |
| Mixer | `audioDebugSummaryLabel` |
| Authentication | `authenticationDebugSummaryLabel` |
| Invite | `inviteDebugSummaryLabel` |
