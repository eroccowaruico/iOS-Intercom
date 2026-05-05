# RTC パッケージ仕様

## 目的

`RTC` は RideIntercom の通話経路を統合する Swift Package として、近距離の `MultipeerConnectivity` と広域の WebRTC を同じ `CallSession` から扱えるようにする。

アプリ本体は UI、グループ管理、secret 管理、音声デバイス選択、診断表示を担当する。`RTC` は接続、経路選択、handover、アプリデータ配送、経路ごとの音声 media 起動停止を担当する。

本パッケージが接続方式差異の全て吸収する。アプリは全く同じ処理を接続方式の区別なく呼び出すことが可能になる。本パッケージは呼び出された接続方式固有処理を無視して取り扱うことが可能。

## 採用方針

| 項目 | 方針 |
|---|---|
| 近距離経路 | `MultipeerConnectivity` を使用する。オフライン動作と低遅延を優先する |
| 広域経路 | native WebRTC SDK を使用する。Cloudflare Realtime SFU and TURN services を前提にする |
| WebRTC public API | `RTC` の public API に native WebRTC 型を露出しない |
| WebRTC 実装配置 | 共通 `RTC` target から分離し、native WebRTC adapter target に閉じ込める |
| WebRTC binary供給 | `webrtc.googlesource.com/src` から自前ビルドした `WebRTC.xcframework` をlocal binary targetとして取り込む |
| 音声codec | `AudioFrameCodec` と `AudioCodecRegistry` で複数codecを扱う。`RTC` はPCM16だけをbuilt-inで持ち、`mpeg4AACELDv2` と `opus` はアプリが `RideIntercom/packages/Audio/Codec` を使ってregistryへ注入する |
| Audio package連携 | `RTC` は `RideIntercom/packages/Audio` に依存しない。アプリが `RTC` と `Audio/Codec` の両方をimportし、`AnyAudioFrameCodec` または `AudioFrameCodec` 実装で橋渡しする |
| サポートOS | RideIntercom本体と同じ最新OSのみを対象にし、iOSとmacOSの最低deployment targetを `26.4` に揃える。Mac CatalystとvisionOSは対象外にする |
| ビルド caveat | native WebRTC binary framework は SwiftPM 単体テストで header 解決に失敗する場合がある。共通 `RTC` target はSDK非依存でテスト可能に保つ |

## パッケージ構成

| パス | 役割 | 代表型 |
|---|---|---|
| `Sources/RTC/Core` | アプリ向けの共通 contract | `CallSession`, `CallStartRequest`, `PeerDescriptor`, `RTCCredential`, `ApplicationDataMessage`, `AudioFrame`, `AudioFrameCodec`, `AudioCodecRegistry` |
| `Sources/RTC/Routing` | 経路 plugin 境界、session factory、自動切替 | `CallSessionFactory`, `CallSessionFactoryConfiguration`, `RTCCallRoute`, `RouteManager`, `AnyRouteFactory`, `UnavailableCallSession` |
| `Sources/RTC/PacketAudio` | Multipeer 用 packet audio と wire payload | `PCM16AudioCodec`, `PCMAudioCodec`, `PacketAudioEnvelope`, `PacketCrypto`, `MultipeerWireMessage` |
| `Sources/RTC/Multipeer` | 近距離 route 実装 | `MultipeerLocalRoute`, `MultipeerConnectionTransport`, `MultipeerPacketMediaSession` |
| `Sources/RTC/WebRTC` | WebRTC 共通 contract と Cloudflare signaling 境界 | `WebRTCInternetRoute`, `NativeWebRTCEngine`, `CloudflareRealtimeConfiguration`, `WebRTCSignalingClient` |
| `Sources/RTC/Support` | 小さな共通補助 | `EventSource` |
| `Sources/RTCNativeWebRTC` | native WebRTC adapter | `WebRTCNativeEngine` |

```mermaid
flowchart TB
    App[RideIntercom App] --> Session[RTC.CallSession]

    subgraph Core[RTC target]
        Session --> Manager[RouteManager]
        Manager --> RouteAPI[RTCCallRoute]
        RouteAPI --> MCRoute[MultipeerLocalRoute]
        RouteAPI --> WebRoute[WebRTCInternetRoute]
        WebRoute --> EngineAPI[NativeWebRTCEngine]
        WebRoute --> Signaling[WebRTCSignalingClient]
    end

    subgraph Adapter[RTCNativeWebRTC target]
        NativeEngine[WebRTCNativeEngine]
    end

    subgraph NativeSDK[External SDK]
        LibWebRTC[WebRTC.xcframework]
    end

    EngineAPI -. implemented by .-> NativeEngine
    NativeEngine --> LibWebRTC
    MCRoute --> Multipeer[MultipeerConnectivity]
    Signaling --> Cloudflare[Cloudflare Realtime SFU and TURN]
```

## アプリとの責務境界

| 領域 | RideIntercom App | RTC |
|---|---|---|
| UI | 表示、操作、アクセシビリティ、診断画面 | UIを持たない |
| グループ | group ID、secret、表示名、招待導線を管理 | `RTCCredential` と `PeerDescriptor` だけを受け取る |
| 音声デバイス | 入出力デバイス選択、OS permission、アプリ側音声処理 | routeごとの media lifecycle を制御する |
| 音声codec実装 | `RideIntercom/packages/Audio/Codec` を使い、RTC向け `AudioFrameCodec` としてregistryへ注入する | codec contract、codec選択、wire envelope、未対応codecエラーを担当する |
| Multipeer 音声 | `AudioFrame` を生成して `sendAudioFrame` に渡す | 選択codecでencode/decode、packet化、暗号化、送信、受信filterを担当する |
| WebRTC 音声 | WebRTC経路ではサンプル送信をしない | `RTCAudioTrack` の有効化と peer connection を担当する |
| アプリデータ | namespace と payload schema を定義する | binary payload と配送信頼性だけを扱う |
| 接続設定 | ユーザー設定から有効routeを決める | `CallRouteConfiguration` に従って選択とhandoverを行う |

## 公開 contract

| 型 | 説明 |
|---|---|
| `CallSession` | アプリが保持する単一の通話 facade。接続とmedia lifecycleを分けて操作する |
| `CallSessionFactory` | `CallSessionFactoryConfiguration` から package-owned route set を構築し、`CallSession` を返す |
| `CallSessionFactoryConfiguration` | local display name、route設定、packet audio codec registry、WebRTC route factory設定を渡す |
| `WebRTCRouteFactoryConfiguration` | WebRTC route の signaling client、engine、Cloudflare configuration provider を差し替える |
| `CallStartRequest` | local peer、期待peer、credential、audio format、route設定を渡す |
| `CallRouteConfiguration` | 有効route、優先route、fallback、自動復帰、standby/warm設定を定義する |
| `CallSessionEvent` | 接続状態、route状態、member、metrics、application data、errorを通知する |
| `AudioCodecIdentifier` | codecを識別する拡張可能な値型。built-inは `pcm16`、`mpeg4AACELDv2`、`opus`、`route-managed` を定義する |
| `AudioCodecConfiguration` | `CallStartRequest` に含めるcodec優先順。空配列は `pcm16` に正規化する |
| `AudioFrameCodec` | `AudioFrame` と `EncodedAudioFrame` の相互変換を行うcodec実装境界 |
| `AnyAudioFrameCodec` | アプリがclosureで `Audio/Codec` との橋渡しを作るための軽量wrapper |
| `AudioCodecRegistry` | codec実装を登録し、優先順とroute対応codecから使用codecを選択する |
| `PacketAudioReceiveConfiguration` | Multipeer packet audio の playout delay と packet lifetime を route へ渡す設定 |
| `RouteMetrics` | route共通のRTT、jitter、packet loss、peer数、audio playout delay、音声受信/drop/queue数を通知する |
| `RTCRuntimeStatus` | package が生成する接続、route、media、codec設定、local control状態のruntime snapshot |
| `RTCRuntimeStatusTransport` | package-owned namespace の `ApplicationDataMessage` として runtime snapshot をencode/decodeする |
| `RTCRuntimePackageReport` | SessionManager / Codec / AudioMixer など他 package が生成した Codable runtime report をRTC statusへ同梱する汎用payload |
| `RTCRuntimeStatusPolicy` | 接続時、変更時、定期送信の有効化と周期を指定する |
| `RTCCallRoute` | `RouteManager` が扱う経路plugin境界。アプリは直接保持しない |
| `NativeWebRTCEngine` | `WebRTCInternetRoute` が使うWebRTC engine抽象。native SDK型を隠す |

## 接続とmediaの分離

| lifecycle | 意味 | Multipeer | WebRTC |
|---|---|---|---|
| `prepare` | credential、peer、audio format、route設定を受け取る | advertiser/browser準備 | signalingとengine準備 |
| `startConnection` | control planeを開始する | discovery、invite、handshake | Cloudflare signaling接続、room参加 |
| `startMedia` | 音声mediaを開始する | packet audioを送受信可能にする | `RTCAudioTrack` を有効化する |
| `stopMedia` | 音声mediaだけ停止する | packet audio送受信を止める | `RTCAudioTrack` を無効化する |
| `stopConnection` | route接続を終了する | `MCSession` と discovery を終了する | signalingとpeer connectionを終了する |

接続済みでもmedia未開始の状態を正式な状態として扱う。これにより、接続準備、認証、member同期、アプリデータ配送を音声開始より先に成立させられる。

## Control Plane と Media Plane

| 種別 | Multipeer | WebRTC |
|---|---|---|
| discovery | Bonjour service `ride-intercom` | Cloudflare room / participant |
| 認証 | group hash と HMAC handshake | Cloudflare participant token と app-level credential |
| route内部control | `MultipeerWireMessage.control` | signaling または DataChannel |
| アプリデータ | `MultipeerWireMessage.applicationData` | `RTCDataChannel`、失敗時は signaling fallback |
| 音声media | `MultipeerWireMessage.packetAudio` | RTP/SRTP media stream |
| 音声codec | `AudioCodecRegistry` で選択したpacket audio codec | WebRTC native codec selection |

`ApplicationDataMessage` は namespace、payload、配送信頼性だけを持つ。RTC内部の handshake、keepalive、fallback diagnostics はアプリ定義 namespace に混ぜない。package が送る runtime status は package-owned namespace を使い、同じ配送面だけを共有する。

## Runtime status

`RTC` は route ごとの接続方式差異を App に露出させず、`RTCRuntimeStatus` として現在値を送信する。App は `ApplicationDataMessage` の任意 namespace を解釈する必要がある場合だけ `RTCRuntimeStatusTransport.decode(_:)` を呼び、表示文字列や route 固有の状態推測を App 側へ固定しない。

| 項目 | 仕様 |
|---|---|
| namespace | `rideintercom.rtc.runtimeStatus` |
| 送信契機 | `RouteManager` が接続開始、route状態変更、media開始/停止、local mute / output mute / remote volume変更、package report更新、定期周期で送信する |
| delivery | routeがunreliable application dataに対応する場合は `.unreliable`、非対応の場合は `.reliable` を使う |
| periodic | `RTCRuntimeStatusPolicy.periodicInterval` に従う。既定は5秒。`nil` または0以下で定期送信しない |
| 受信 | 通常の `.receivedApplicationData` として通知し、`RTCRuntimeStatusTransport.decode(_:)` で package status か判定できる |
| 状態粒度 | session ID、local / expected peers、`CallConnectionState`、media開始状態、mute、peer volume、active/media route、route availability、route capabilities、media ownership、selected audio codec、route設定、audio format、codec設定、他packageのruntime report |
| package report | `updateRuntimePackageReports(_:)` で `RTCRuntimePackageReport` を渡す。RTC はpayloadを解釈せず、package名、kind、contentType、payloadをstatusへ同梱する |
| App境界 | App は RTC接続状態、通信設定、codec設定、media ownership を表示用に再構成しない。package status をそのまま Diagnostics の入力にする |

## Audio codec

| 項目 | 仕様 |
|---|---|
| codec識別子 | `AudioCodecIdentifier` は文字列値型とする。固定enumにせず、Audio packageや将来codecが独自identifierを追加できるようにする |
| Audio/Codecとの対応 | `pcm16`、`mpeg4AACELDv2`、`opus` は `Audio/Codec.CodecIdentifier.rawValue` と同じ文字列にする |
| codec設定 | `CallStartRequest.audioCodecConfiguration.preferredCodecs` に優先順を渡す。既定は `pcm16` とする |
| codec実装 | `AudioFrameCodec` が `AudioFrame` から `EncodedAudioFrame` へのencodeと、逆方向のdecodeを提供する |
| app bridge | アプリは `Audio/Codec.AudioCodec` のencode/decodeを `AnyAudioFrameCodec` または独自 `AudioFrameCodec` に包み、`AudioCodecRegistry` として `CallSessionFactoryConfiguration.packetAudioCodecRegistry` に渡す |
| codec登録 | `AudioCodecRegistry` に複数の `AudioFrameCodec` を登録する。登録済みcodecだけがpacket audio routeで選択可能になる |
| built-in codec | `PCM16AudioCodec` を標準提供する。既存の `PCMAudioCodec.encode/decode` はAudio/CodecのPCM16と同じsigned little-endian変換に揃える |
| 未対応codec | 優先codecとroute対応codecが一致しない場合は `unsupportedAudioCodec` を通知し、routeをavailableにしない |
| wire envelope | `EncodedAudioFrame.codec`、`AudioFormatDescriptor`、sequence、capturedAt、sampleCount、payloadを保持する。受信側はcodec identifierでdecode実装を選ぶ |
| WebRTC route | `route-managed` として扱う。アプリから `sendAudioFrame` されたPCM/encoded packetをWebRTCへ流さず、native WebRTC側のcodec negotiationに任せる |

| codec | 提供元 | RTC依存 | Audio package連携 | 主用途 |
|---|---|---|---|---|
| `pcm16` | `RTC` built-in | なし | Audio package不要 | Multipeer packet audioの標準経路とテスト基準 |
| `mpeg4AACELDv2` | `Audio/Codec` | `RTC` はidentifierだけを定義 | アプリが `AudioFrameCodec` としてregistryへ注入 | AVFoundation系低遅延codec候補 |
| `opus` | `Audio/Codec` | `RTC` はidentifierだけを定義 | アプリが `AudioFrameCodec` としてregistryへ注入 | 低bitrate packet audio候補 |
| `route-managed` | route実装 | `WebRTCInternetRoute` のcapabilityで表現 | Audio packageとは接続しない | WebRTC native media stream |

| アプリでの接続手順 | 依存方向 | 実装内容 | 完了条件 |
|---|---|---|---|
| package import | App -> RTC / App -> Audio/Codec | アプリtargetが `RTC` と `Codec` をimportする | `RTC` package manifestにAudio package dependencyを追加しない |
| format変換 | App内 | `AudioFormatDescriptor` と `CodecAudioFormat` を同じsampleRate/channelCountで相互変換する | アプリがOSやroute別にformat差分を持ち込まない |
| codec変換 | App内 | `EncodedAudioFrame` と `EncodedCodecFrame` を同じsequence/capturedAt/sampleCount/payloadで相互変換する | packet audio envelopeがAudio/Codecのdecodeに必要なmetadataを失わない |
| registry注入 | App -> RTC | `AudioCodecRegistry(codecs:)` を作り `CallSessionFactoryConfiguration.packetAudioCodecRegistry` に渡す。RTC package が必要な route に registry を配る | `CallStartRequest.audioCodecConfiguration.preferredCodecs` の優先順でcodecが選ばれる |
| built-in fallback | RTCのみ | `PCM16AudioCodec` を使用する | Audio/Codecをまだ接続しなくてもRTC単体テストとMultipeer packet audioが動作する |

## 音声責務

| 経路 | `AudioMediaOwnership` | アプリから `sendAudioFrame` | RTC側責務 |
|---|---|---|---|
| Multipeer | `appManagedPacketAudio` | 使用する | codec選択、encode、encrypt、sequence、receive filter、decode、send/receive |
| WebRTC | `routeManagedMediaStream` | 使用しない | `RTCAudioTrack`、peer connection、DataChannel、stats取得境界 |

`RouteManager` は active route が `appManagedPacketAudio` を持つ場合だけ `sendAudioFrame` を転送する。WebRTC active時にアプリが `sendAudioFrame` を呼んでも、音声サンプルは route に渡さない。

## 経路選択

| 設定 | 意味 |
|---|---|
| `enabledRoutes` | ユーザー設定で opt-in / opt-out されたrouteだけを使用する |
| `preferredRoute` | 最初に接続するroute。通常は `.multipeer` |
| `selectionMode.singleRoute` | 優先routeだけを使う |
| `selectionMode.automaticFallback` | 優先routeが失敗したら別routeへ切り替える |
| `selectionMode.automaticFallbackAndRestore` | fallback後も優先routeを監視し、復帰可能なら戻す |
| `startsStandbyConnections` | fallback候補routeを接続standbyまで進める |
| `keepsPreviousRouteWarmDuringHandover` | handover中に旧routeを即切断せず、media fade後に停止する |

アプリは route 実体を組み立てない。アプリは `CallSessionFactoryConfiguration` に `CallRouteConfiguration` と bridge 済みの `AudioCodecRegistry` を渡し、RTC package が `.multipeer` と `.webRTC` の route set を構築する。これにより route 追加、WebRTC engine 差し替え、signaling 差し替え、fallback policy は RTC package の責務として閉じる。

```mermaid
sequenceDiagram
    participant App as RideIntercom App
    participant Session as RTC.CallSession
    participant Manager as RouteManager
    participant MC as MultipeerLocalRoute
    participant WEB as WebRTCInternetRoute
    App->>Session: prepare request
    Session->>Manager: prepare enabled routes
    Manager->>MC: prepare
    Manager->>WEB: prepare
    App->>Session: startConnection
    Manager->>MC: startConnection
    Manager->>WEB: startConnection when standby enabled
    MC-->>Manager: failed or disconnected
    Manager->>WEB: handover startConnection
    WEB-->>Manager: connected
    App->>Session: startMedia
    Manager->>WEB: startMedia
    MC-->>Manager: available again
    Manager->>MC: restore when policy allows
```

## Multipeer route

| 項目 | 仕様 |
|---|---|
| service type | `ride-intercom` |
| discovery info | `groupHash` を含める |
| invite context | `groupHash` を含める |
| handshake | `RouteHandshakeMessage` を HMAC-SHA256 で検証する |
| payload | `MultipeerWireMessage` で control / application data / packet audio を分離する |
| 暗号化 | packet audio payload は `RTCCredential.sharedSecret` から AES-GCM で保護する |
| media開始前 | control と handshake は可能。packet audioは送受信しない |
| codec選択 | `CallStartRequest.audioCodecConfiguration.preferredCodecs` と `MultipeerLocalRoute` の `AudioCodecRegistry.supportedCodecs` から最初に一致したcodecを使う |
| codec注入 | `MultipeerLocalRoute(displayName:codecRegistry:packetAudioReceiveConfiguration:)` で外部codecと受信timing設定を注入できる。未指定時は `PCM16AudioCodec` と標準receive設定を使う |
| 重複排除 | `PacketAudioReceiveFilter` が `peerID + sequenceNumber` の重複packetを破棄する |
| playout制御 | route内部の受信bufferが受信済みpacketを指定delay後に peer / sequence 順で `receivedAudioFrame` event として渡す |
| 受信診断 | ready化、期限切れdrop、queue数は public buffer report ではなく `RouteMetrics` に正規化して通知する |

## WebRTC route

| 項目 | 仕様 |
|---|---|
| backend | Cloudflare Realtime SFU and TURN services |
| signaling | `WebRTCSignalingClient` で差し替え可能にする |
| native SDK | `RTCNativeWebRTC.WebRTCNativeEngine` がlocal binary targetの `WebRTC.xcframework` を使用する |
| public API | `WebRTCSessionDescription`, `WebRTCIceCandidate`, `WebRTCIceServer` のwrapperだけを公開する |
| audio | `RTCAudioTrack` をroute-managed mediaとして扱う |
| offer / answer | remote peer 参加時に offer を生成し、incoming offer には peer connection を確保して answer を返す |
| ICE candidate | native engine が生成した local candidate を `WebRTCSignalingClient` へ渡す |
| app data | `RTCDataChannel` を優先し、未接続時は signaling client にfallbackする |
| DataChannel受信 | `ApplicationDataMessage` としてdecodeし、`RouteEvent.receivedApplicationData` へ正規化する |
| build分離 | `RTC` targetはnative SDK非依存、`RTCNativeWebRTC` targetだけが `import WebRTC` する |

### WebRTC binary の自前ビルド

| 項目 | 方針 |
|---|---|
| source | `https://webrtc.googlesource.com/src` を使用する |
| checkout | Chromium / WebRTC source は RideIntercom repository に含めない。`WEBRTC_BUILD_ROOT` 配下に取得する |
| depot_tools | `DEPOT_TOOLS_DIR` で指定する。未指定時はrepository親ディレクトリの `../depot_tools` を使う |
| build wrapper | `scripts/build-webrtc-xcframework.sh` を使用する |
| 通常コマンド | `scripts/build-current-webrtc-xcframework.sh` を使用する。`WEBRTC_BRANCH` 未指定時はChromium DashboardからstableのWebRTC branch-headを取得する |
| header検証 | `scripts/verify-webrtc-xcframework.sh` で `RTCAudioSource.h`、`RTCPeerConnection.h`、`RTCDataChannel.h` などを各sliceで検証する |
| 成果物 | 検証済みの `WebRTC.xcframework` を binary target の入力にする。巨大なWebRTC source treeはcommitしない |
| 後片付け | `scripts/clean-webrtc-build-resources.sh` を使用する。標準はdry-runで、削除時は `DRY_RUN=false` を明示する |

| platform | build target | framework構造 | 差分の扱い |
|---|---|---|---|
| iOS device | `framework_objc` / `target_os="ios"` / `target_environment="device"` | `WebRTC.framework/Headers` | arm64のみをxcframework sliceに入れる |
| iOS simulator | `framework_objc` / `target_os="ios"` / `target_environment="simulator"` | `WebRTC.framework/Headers` | x86_64とarm64をlipoで統合する |
| macOS | `mac_framework_objc` / `target_os="mac"` | `WebRTC.framework/Versions/A/Headers` | x86_64とarm64をlipoで統合する。Headers欠落がある場合はiOS device sliceのpublic headersで補完してから検証する |

`CloudflareRealtimeSignalingClient` は production 実装ではなく placeholder とする。実運用では Cloudflare room作成、participant token、offer / answer / ICE candidate 送受信を実装した `WebRTCSignalingClient` を注入する。

## Handover

| 状態 | 動作 |
|---|---|
| active route が失敗 | `RouteManager` が fallback候補を選び、`startConnection` を呼ぶ |
| media開始済み | 新routeでmediaを開始し、`handoverFadeDuration` 後に旧routeのmediaを止める |
| 旧route warm維持 | 設定が有効なら旧connectionは維持し、mediaだけ止める |
| 優先route復帰 | `automaticFallbackAndRestore` の場合だけ優先routeへ戻す |
| 有効routeなし | `UnavailableCallSession` が明示的に `noEnabledRoute` を通知する |

## テスト方針

| テスト対象 | 検証内容 |
|---|---|
| wire payload | application data と packet audio が別 payload として扱われる |
| codec selection | 優先codecがregistryに存在する場合、そのcodec identifierがpacket audio envelopeに保持される |
| codec rejection | 優先codecがregistryに存在しない場合、packet audio routeが未対応codecとして失敗する |
| route filtering | `enabledRoutes` でopt-outされたrouteを準備しない |
| fallback | Multipeer失敗時にWebRTCへ自動切替する |
| audio ownership | `routeManagedMediaStream` active時に `sendAudioFrame` を転送しない |
| packet audio receive filter | 重複packetが `PacketAudioReceiveFilter` で破棄される |
| packet audio receive buffer | delay前のframeを返さず、ready frameを peer / sequence 順で返し、期限切れframeをdrop数へ反映する |
| packet audio metrics | 受信数、drop数、queue数が `RouteMetrics` に正規化される |
| SDK adapter | local binary targetのSwiftPM解決と `RTCNativeWebRTC` buildを検証する |

## 実装上の注意

| 項目 | 注意 |
|---|---|
| native型の漏れ | app-facing API と `RTC` target public API に `RTCPeerConnection` などを出さない |
| route追加 | 新routeは `RTCCallRoute` と `RouteCapabilities` から追加する |
| codec追加 | 新codecはアプリ側で `AudioFrameCodec` 実装または `AnyAudioFrameCodec` として登録する。`RTC` targetからAudio packageへ直接依存しない |
| app data schema | アプリ定義 namespace のschemaはRTC packageに置かない。RTC runtime status の package-owned namespace だけは `RTCRuntimeStatusTransport` で定義する |
| audio format | Multipeer packet audioではcodec identifier、`AudioFormatDescriptor`、sampleCountをwire envelopeに含める |
| 診断 | TX/RX/JIT、route metrics、backend detail はCall画面ではなくDiagnosticsへ集約する |
| サーバー | Cloudflare以外の独自サーバー機能は追加しない |
