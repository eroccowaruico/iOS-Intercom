# App 側に残る package 要求

## 目的

本書は、App 側で見つかった package の不足責務を記録する。

解決済みの棚卸しや、App 側暫定実装の正当化はここに残さない。`docs/spec/packages` の仕様で吸収すべき不足が見つかった場合だけ、package 要求として追記する。

## 現在の package 要求

| package | 不足している責務 | App に暫定実装しない理由 | App から消す条件 |
|---|---|---|---|
| SessionManager | `AudioInputStreamCapture` が入力 stream 実行中の `AudioInputVoiceProcessingConfiguration` 更新を受け取り、適用結果を report / runtime event として通知できること | voice processing は `AudioInputStreamConfiguration` に含まれる入力 stream の設定であり、App が同じ `AVAudioEngine.inputNode` に対して `AudioInputStreamCapture` と `AudioInputVoiceProcessingManager` を別々に握るのは抽象境界が割れている。App はサウンド分離、ducking、ducking level、input mute の変更時に OS / 環境差異を見ず、同じ stream API へ設定を渡せるべき | `AudioInputStreamCapture` に、未開始時も実行中も同じ呼び出しで使える voice processing 更新 API がある。適用、非対応 no-op、継続可能失敗を `AudioStreamOperationResult` 相当で返し、同じ内容を `AudioStreamRuntimeEvent` でも購読できる。iOS / macOS 差異は package 内で吸収され、App 側に OS 分岐や `AVAudioInputNode` 直操作が残らない |

## 現在 App 側に残っている回避

| 場所 | 内容 | 消す理由 |
|---|---|---|
| `RideIntercom/Intercom/ViewModel/IntercomViewModel+Factory.swift` | `AVAudioEngine`、`SystemAudioInputStreamBackend`、`AudioInputVoiceProcessingManager` を同じ input node に対して組み立てている | input stream capture の利用者が runtime voice processing 更新のために backend / manager 構成を知る必要がある |
| `RideIntercom/Intercom/ViewModel/IntercomViewModel+CallLifecycle.swift` | 通話開始時に `applyCurrentVoiceProcessingConfiguration()` を呼ぶ | stream 開始と voice processing 適用の責務が App 側で分離している |
| `RideIntercom/Intercom/ViewModel/IntercomViewModel+AudioSettings.swift` | mute、sound isolation、ducking 設定変更時に `applyCurrentVoiceProcessingConfiguration()` を呼ぶ | App が stream 抽象ではなく voice processing manager の存在を前提にしている |

## 追記ルール

| 記録する項目 | 内容 |
|---|---|
| package | 変更対象 package |
| 不足している責務 | App ではなく package が持つべき責務 |
| App に暫定実装しない理由 | package 独立性、OS差分吸収、準異常系処理、runtime 情報通知、設定受け取りのどれに関わるか |
| App から消す条件 | どの package API / runtime event / report があれば App が同一呼び出しで使えるか |
