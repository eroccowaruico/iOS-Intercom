# RideIntercom Diagnostics 画面項目

## 目的

本書は Diagnostics タブの UI 項目を定義する。

Diagnostics はログを読む代替ではない。音声 pipeline の現在状態は送信/受信パイプラインで見せ、現在状態一覧は pipeline から読み取れない App 状態と network quality に絞る。

## 画面構成

| 項目名（日本語） | 項目ID | 目的 | 実装 | 更新周期 | 表示仕様 |
|---|---|---|---|---|---|
| 診断画面 | `diagnostics-screen` | package runtime report と App 状態を要約する | `DiagnosticsView` | 0.5 秒 | `TimelineView` + `ScrollView` |
| 送信パイプライン | `diagnostics-live-pipeline` | ローカル送信がどこまで進んでいるかを読む | `LiveTransmitPipelineView` | 0.5 秒 | compact row。effect chain は TX bus 内に内包表示 |
| 受信パイプライン | `diagnostics-live-rx-pipeline` | 受信音声が出力までどこまで進んでいるかを読む | `LiveReceivePipelineView` | 0.5 秒 | compact row。peer bus は複数行一覧、effect chain は該当 bus 内に内包表示。RX master FX は最後に PeakLimiter を持つ |
| 現在状態一覧 | `diagnostics-overview-grid` | pipeline と重複しない App 状態を見る | `DiagnosticsOverviewGrid` | 0.5 秒 | adaptive grid。Call / Network Quality / Invite のみ |

## 送信パイプライン

| 項目名（日本語） | 親項目 | 項目ID | ラベル | データ仕様 | 表示仕様 | 状態・異常系の考え方 |
|---|---|---|---|---|---|---|
| SessionManager sessionステップ | `diagnostics-live-pipeline` | `pipeline-session-step` | Session | `AudioSessionSnapshot`, `audioSessionProfile`, 直近 session report | 状態アイコン + profile | session error は blocked |
| SessionManager inputステップ | `diagnostics-live-pipeline` | `pipeline-input-step` | Input | `AudioInputStreamCapture` snapshot、voice processing report、`isMuted` | stream format、frame count、mute | ミュートは故障ではなく waiting |
| AudioMixer TX busステップ | `diagnostics-live-pipeline` | `pipeline-mixer-step` | TX Bus | TX bus / source / routing 状態 | `Mic -> FX` として表示 | mixer 未開始は neutral |
| AudioMixer effect chainステップ | `diagnostics-live-pipeline` | `pipeline-effects-step` | FX Chain | `transmitEffectChainSnapshot.stages` | TX bus 配下の inline stage chip として表示 | stage 内の unavailable / bypassed を warning 以下で表示 |
| codec ステップ | `diagnostics-live-pipeline` | `pipeline-codec-step` | Codec | `preferredTransmitCodec`, `selectedTransmitCodec` | requested と selected を表示。fallback 時は `requested -> selected / Fallback` | fallback は warning |
| RTC ステップ | `diagnostics-live-pipeline` | `pipeline-rtc-step` | RTC | `sentVoicePacketCount`, route, media ownership | packet 送信数と route | 送信 0 は未発話または未接続として読む |

## 送信 effect chain 表示

effect chain は App runtime が持つ `transmitEffectChainSnapshot` を表示する。Diagnostics は effect の既定値や stage 配列を持たない。Diagnostics では FX Chain 行の下へ stage chip をインライン表示し、TX bus の内包関係が見えるようにする。

| stage | accessibilityIdentifier | package | 表示する状態 |
|---|---|---|---|
| SoundIsolation | `pipeline-effect-stage-sound-isolation` | SoundIsolation | enabled / bypassed / unavailable |
| VADGate | `pipeline-effect-stage-vad-gate` | VADGate | speech / silent / muted、感度 preset、noise floor、threshold、gate gain |
| DynamicsProcessor | `pipeline-effect-stage-dynamics-processor` | DynamicsProcessor | leveling ready / idle |
| PeakLimiter | `pipeline-effect-stage-peak-limiter` | PeakLimiter | peak guard ready / idle |

| 拡張ルール | 仕様 |
|---|---|
| stage 追加 | App runtime の effect chain snapshot に stage を追加するだけで Diagnostics の表示順へ反映する |
| 固定文字列禁止 | `SoundIsolation -> VADGate -> DynamicsProcessor -> PeakLimiter` のような固定文言や default 値を UI の正本にしない |
| 一覧性 | stage が増えた場合は FX Chain 行の内側で折り返し、ログを読まなくても各 stage の現在状態を読めるようにする |

## 受信パイプライン

| 項目名（日本語） | 親項目 | 項目ID | ラベル | データ仕様 | 表示仕様 | 状態・異常系の考え方 |
|---|---|---|---|---|---|---|
| RTC受信ステップ | `diagnostics-live-rx-pipeline` | `receive-pipeline-rtc-step` | RTC RX | route、connected peer count、authenticated peer count、受信 packet count、media ownership | route と総 RX count。内側の `receive-rtc-peers` で接続 peer 名、RTC 接続状態、認証状態を一覧表示 | 受信 0 は未発話または未接続として読む |
| Codec decodeステップ | `diagnostics-live-rx-pipeline` | `receive-pipeline-codec-step` | Decode | peer ごとの `activeCodec`、peer ごとの RX count、drop count | codec の集約サマリは出さない。内側の `receive-codec-peers` で peer 名と decode codec を一覧表示 | drop は warning |
| peer busステップ | `diagnostics-live-rx-pipeline` | `receive-pipeline-peer-bus-step` | Peer Buses | authenticated peer count、peer 別 RX / JIT / PLAY / level / volume / `receivePeerEffectChainSnapshot(peerID:)` | bus 数と RX count。下段に peer bus を複数行一覧で表示し、各 peer row 内には Mixer bus と effect chain だけを表示 | peer なしは neutral / waiting |
| receive mix downステップ | `diagnostics-live-rx-pipeline` | `receive-pipeline-mix-step` | Mix Down | peer bus count、受信 packet count | `n buses -> master` として複数 peer が master に集約されることを表示 | bus なしは waiting |
| receive master busステップ | `diagnostics-live-rx-pipeline` | `receive-pipeline-master-bus-step` | RX Master | played frame count、master volume、source bus count | source bus count と OUT volume。mix 後の 1 本の master bus として表示 | 再生 0 は waiting |
| master effect chainステップ | `diagnostics-live-rx-pipeline` | `receive-pipeline-master-effects-step` | Master FX | `receiveMasterEffectChainSnapshot.stages` | RX Master 配下に適用される ordered stage chip として inline 表示。最後は PeakLimiter | stage 単位で unavailable / bypassed を表示 |
| outputステップ | `diagnostics-live-rx-pipeline` | `receive-pipeline-output-step` | Output | output renderer snapshot、mute、volume | stream format、frame count、mute | mute / volume 0 は warning |

## 受信 mix topology 表示

`LiveReceivePipelineView` は RTC、Decode、Peer Buses の各ステップに peer 別の内訳を持つ。RTC の内側では誰が接続・認証されているかを表示し、Decode の内側では peer ごとの codec を表示し、Peer Buses の内側では Mixer bus と effect chain を表示する。

`receive-pipeline-peer-bus-step` の内側にある `receive-mix-topology` では peer bus が複数行で並び、最後に receive master bus へ mix down される構造をログなしで確認できるようにする。peer が増えても巨大な card grid へせず、各 peer は RX / JIT / PLAY / level / volume / effect chain を compact row と chip で表示する。

| 項目 | accessibilityIdentifier | 表示する状態 |
|---|---|---|
| RTC peer group | `receive-rtc-peers` | 接続対象 peer の一覧 |
| RTC peer row | `receive-peer-rtc-{index}` | peer 名、RTC 接続状態、認証状態 |
| Decode peer group | `receive-codec-peers` | peer ごとの decode codec 一覧 |
| Decode peer row | `receive-peer-codec-{index}` | peer 名、decode codec、RX count |
| peer bus 空状態 | `receive-peer-buses-empty` | 認証済み peer bus がまだない |
| peer bus row | `receive-peer-bus-{index}` | peer 名、RX / JIT / PLAY、peer volume、peer ごとの effect summary、現在 level |
| peer bus effect stage | `receive-peer-{index}-effect-stage-{stageID}` | その peer の `receivePeerEffectChainSnapshot(peerID:)` に含まれる stage 状態 |
| master mix row | `receive-master-mix-card` | source bus count、総 RX、PLAY、master volume / mute、RX master effect summary、出力 level |

## 受信 effect chain 表示

受信側は peer bus と receive master bus のそれぞれに ordered stages を持つ。Diagnostics は `receivePeerEffectChainSnapshot(peerID:)` と `receiveMasterEffectChainSnapshot` を描画するだけで、effect の default 値や stage 配列を持たない。peer 側は全体で 1 つの共有 Peer FX 行にまとめず、各 peer row の内側へ inline 表示する。

| chain | stage | accessibilityIdentifier | package | 表示する状態 |
|---|---|---|---|---|
| Peer FX | SoundIsolation | `receive-peer-{index}-effect-stage-sound-isolation` | SoundIsolation | enabled / bypassed / unavailable |
| Master FX | SoundIsolation | `receive-master-effect-stage-sound-isolation` | SoundIsolation | enabled / bypassed / unavailable |
| Master FX | PeakLimiter | `receive-master-effect-stage-peak-limiter` | PeakLimiter | final peak guard ready / idle |

| 拡張ルール | 仕様 |
|---|---|
| stage 追加 | App runtime の peer または master effect chain snapshot に stage を追加するだけで Diagnostics の表示順へ反映する |
| RX master limiter | RX master effect chain の最後には必ず PeakLimiter を表示する。ユーザー設定の対象にはしない |
| 固定文字列禁止 | 受信側も固定の effect 名列挙や default 値を UI の正本にしない |
| 一覧性 | peer chain は peer row 内、master chain は RX master row 内で別々に表示し、どちらで処理が止まっているかをログなしで読めるようにする |
| 表示順検証 | Diagnostics の effect chip は `AudioEffectChainSnapshot.stages` の登録順をそのまま使う。任意 stage を追加した順序が UI 表示用 model へ保持されることをテストする |

## 受信 peer metadata

| 項目 | 仕様 |
|---|---|
| codec metadata | keepalive metadata に remote peer の active codec を載せ、受信側の `GroupMember.activeCodec` に反映する |
| decode 表示 | Diagnostics は `activeCodec` を Decode ステップ内の `receive-peer-codec-{index}` に `DEC ...` として表示する。未受信または metadata 未到達の場合は `Unknown` とする |
| RTC 接続表示 | `GroupMember.connectionState` と `GroupMember.authenticationState` を RTC ステップ内の `receive-peer-rtc-{index}` に表示する |

## 現在状態一覧

| 項目名（日本語） | 項目ID | ラベル | データ仕様 | 表示仕様 | severity |
|---|---|---|---|---|---|
| 通話カード | `diag-call-route-summary` | `Call` | `connectionLabel`, selected group summary | `CALL {state}` / selected group | 接続中は ok、未接続は neutral |
| network qualityカード | `diag-network-quality-summary` | `Network Quality` | `RouteMetrics.rtt`, `RouteMetrics.packetLoss`, `RouteMetrics.jitter` | RTT、loss、jitter。route / RX / drop / queue は pipeline 側を見る | loss は warning |
| 招待カード | `diag-invite-summary` | `Invite` | invite URL、invite status、selected group | `INVITE ...` / group summary | 招待可能なら ok |

## 一覧性のルール

| 項目 | 仕様 |
|---|---|
| 表示粒度 | 1 カードは 1 つの層だけを示す。複数層の原因推測を 1 行へ詰め込まない |
| 文字量 | summary は 1 行、detail は補足。長文ログや stack trace は置かない |
| 色 | ok / warning / error / neutral をカード左アイコン色で示す |
| 表示順 | Call、Network Quality、Invite の順を維持する |
| ログとの関係 | Diagnostics で現在値を読み、ログは操作境界や失敗の後追い調査に使う |
| 環境差異 | unsupported / ignored は warning 以下に留め、継続可能な状態として表示する |
| パイプライン表示 | 各 pipeline step を大きな独立 card にしない。1 step は compact row、stage は親 row の内側の chip として表示する |
| 受信 peer 表示 | peer bus は複数人を前提に 1 peer 1 行で表示する。peer 数が増えても topology 全体を巨大 card grid にしない |
| overview の重複禁止 | Session、Input、Output、Codec、Mixer、Authentication など pipeline で読める値は現在状態一覧へ再掲しない |

## Accessibility Identifier

既存 UI テストと調査導線を壊さないため、一覧カードは旧 debug label の identifier を維持する。

| カード | accessibilityIdentifier |
|---|---|
| Call | `realDeviceCallDebugSummaryLabel` |
| Network Quality | `receptionDebugSummaryLabel` |
| Invite | `inviteDebugSummaryLabel` |
