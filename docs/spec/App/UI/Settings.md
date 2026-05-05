# RideIntercom Settings 画面項目

## 目的

本書は Settings タブの UI 項目を定義する。

Settings は Audio Session、入出力、Audio Check、送信 codec、VAD、設定リセットを扱う。設定値の型、既定値、永続化は `docs/spec/App/setting parameters/App/設定値一覧.md` を正とする。

## 親セクション

| 項目名（日本語） | 項目ID | 目的 | 実装 | 発現条件 | 表示仕様 |
|---|---|---|---|---|---|
| 設定画面 | `settings-screen` | 通話前後の調整、確認、自己診断を行う | `SettingsView` | 常時 | `Form` |
| Audio Session設定 | `settings-audio-session` | SessionManager の mode、speaker、echo cancellation、Duck Other Audio の組み合わせを選択する | `AudioSessionPanel` | 常時 | `Audio Session` section |
| 音声I/O設定 | `settings-audio-io` | 入出力ポートと effect chain の有効/無効を選択する | `AudioIOPanel` | 常時 | `Audio I/O` section |
| オーディオチェック設定 | `settings-audio-check` | 自己録音/再生で経路確認する | `AudioCheckPanel` | 常時 | `Audio Check` section |
| 送信コーデック設定 | `settings-transmit-codec` | 送信 codec と bitrate を選ぶ | `TransmitCodecPanel` | 常時 | `Transmit Codec` section |
| Voice Activity設定 | `settings-voice-activity` | 発話検出の感度を調整する | `VoiceActivityPanel` | 常時 | `Voice Activity` section |
| 設定リセット | `settings-reset` | 調整値だけを既定へ戻す | `ResetSettingsPanel` | 常時 | 最下部 |

## Audio Session

| 項目名（日本語） | 親項目 | 項目ID | ラベル | データ仕様 | 発現条件 | 表示仕様 | 異常系の考え方 |
|---|---|---|---|---|---|---|---|
| Session mode選択 | `settings-audio-session` | `audioSessionProfilePicker` | `Mode` | `.standard` / `.voiceChat`。既定は `Burst mode` | 常時 | `Picker(.menu)`。表示は `Burst mode` / `Stream mode` | `.speakerDefault` は画面選択肢に出さない |
| スピーカー出力設定 | `settings-audio-session` | `speakerOutputToggle` | `Use Speaker` | `Bool` | 常時 | Toggle | speaker 出力希望は mode と独立して選ぶ。`Stream mode` でも ON にできる |
| Echo Cancellation設定 | `settings-audio-session` | `echoCancellationToggle` | `Echo Cancellation` | `Bool`。既定 ON | `Mode == Burst mode` | Toggle。`Use Speaker == true` の場合は ON 固定表示 | `mode = .voiceChat` では session 側 `prefersEchoCancelledInput` を使わない |
| 他音声ダック設定 | `settings-audio-session` | `duckOthersToggle` | `Duck Other Audio` | `Bool`。既定 ON | `supportsAdvancedMixingOptions == true` | Toggle | Audio Session / input voice processing の組み合わせとして扱う。実効発動は可聴な受信出力の有無から導出 |
| Session mode説明 | `settings-audio-session` | `audioSessionModeDescription` | なし | 固定文言 | 常時 | section footer の小さな説明文 | `Burst mode` と `Stream mode` の違いだけを説明する。要求状態や適用結果は Settings に出さず Diagnostics を正とする |

| UI 状態 | SessionManager へ渡す値 | 用途 |
|---|---|---|
| `Burst mode`、`Use Speaker = false`、`Echo Cancellation = false` | `mode = .default`、`defaultToSpeaker = false`、`prefersEchoCancelledInput = false` | 標準。ほかの音声との共存を優先 |
| `Burst mode`、`Use Speaker = false`、`Echo Cancellation = true` | `mode = .default`、`defaultToSpeaker = false`、`prefersEchoCancelledInput = true` | 既定状態。default mode のまま echo cancellation を要求する |
| `Burst mode`、`Use Speaker = true` | `mode = .default`、`defaultToSpeaker = true`、`prefersEchoCancelledInput = true` | スピーカー出力では echo cancellation も同時に要求する |
| `Stream mode`、`Use Speaker = false` | `mode = .voiceChat`、`defaultToSpeaker = false`、`prefersEchoCancelledInput = false` | 電話に近い会話体験やレシーバー利用を優先する |
| `Stream mode`、`Use Speaker = true` | `mode = .voiceChat`、`defaultToSpeaker = true`、`prefersEchoCancelledInput = false` | Stream mode のままスピーカー出力を要求する。明示的な `prefersEchoCancelledInput` は使わない |

## Audio I/O

| 項目名（日本語） | 親項目 | 項目ID | ラベル | データ仕様 | 発現条件 | 表示仕様 | 異常系の考え方 |
|---|---|---|---|---|---|---|---|
| 出力デバイス選択 | `settings-audio-io` | `audio-output-picker` | `Output` | `AudioPortInfo` | `availableOutputPorts.count > 1` | `Picker(.menu)` | 切替失敗は Call の音声エラーと Diagnostics に反映 |
| 入力デバイス選択 | `settings-audio-io` | `audio-input-picker` | `Input` | `AudioPortInfo` | `availableInputPorts.count > 1` | `Picker(.menu)` | 切替失敗は音声デバイス問題として扱う |
| Voice Isolation Effect設定 | `settings-audio-io` | `soundIsolationToggle` | `Voice Isolation Effect` | `Bool` | `supportsSoundIsolation == true` | Toggle | 非対応 platform では非表示。SessionManager の voice processing 設定ではなく SoundIsolation effect chain の有効/無効として扱う |

## Audio Check

| 項目名（日本語） | 親項目 | 項目ID | ラベル | データ仕様 | 発現条件 | 表示仕様 | 状態 |
|---|---|---|---|---|---|---|---|
| 通話/チェック状態表示 | `settings-audio-check` | `audio-check-call-status` | `Call` | `isAudioReady`, `audioCheckPhase` | 常時 | 右寄せ 2 段表示 | Call Live / Call Idle、recording / playing など |
| マイク入力確認 | `settings-audio-check` | `audio-check-input-group` | `Microphone Input` | `diagnosticsInputLevel`, `diagnosticsInputPeakLevel` | 常時 | 入力メーター | 権限未許可時は上がらない |
| スピーカー出力確認 | `settings-audio-check` | `audio-check-output-group` | `Speaker Output` | `diagnosticsOutputLevel`, `diagnosticsOutputPeakLevel` | 常時 | 出力メーター | 最終出力へ回した音声を示す |
| チェック状態メッセージ | `settings-audio-check` | `audio-check-status-message` | 状態文言 | `String` | 常時 | footnote | 実行中、完了、失敗 |
| チェック実行ボタン | `settings-audio-check` | `audio-check-button` | `Record 5s and Play` | Action | 常時 | 録音/再生中は disabled | 二重起動を防ぐ |

## Transmit Codec

| 項目名（日本語） | 親項目 | 項目ID | ラベル | データ仕様 | 発現条件 | 表示仕様 | 状態 |
|---|---|---|---|---|---|---|---|
| 送信コーデック選択 | `settings-transmit-codec` | `transmit-codec-picker` | `Codec` | `preferredTransmitCodec`。既定は `AAC-ELD v2` | 常時 | `Picker(.segmented)`。`PCM 16-bit`、`AAC-ELD v2`、`Opus` | ユーザーが要求する codec |
| AAC-ELD v2 bitrate | `settings-transmit-codec` | `aac-eld-v2-bitrate-picker` | `AAC-ELD v2 Bitrate` | `Int`, `12_000...128_000`。既定 32 kbps | `preferredTransmitCodec == .mpeg4AACELDv2` | `Stepper`、kbps 表示 | Codec package の正規化後の値を表示 |
| Opus bitrate | `settings-transmit-codec` | `opus-bitrate-picker` | `Opus Bitrate` | `Int`, `6_000...128_000`。既定 32 kbps | `preferredTransmitCodec == .opus` | `Stepper`、kbps 表示 | Codec package の正規化後の値を表示 |

## Voice Activity

| 項目名（日本語） | 親項目 | 項目ID | ラベル | データ仕様 | 発現条件 | 表示仕様 | 状態 |
|---|---|---|---|---|---|---|---|
| VAD感度選択 | `settings-voice-activity` | `vad-sensitivity-picker` | `VAD Sensitivity` | `.lowNoise` / `.standard` / `.noisy` | 常時 | `Picker(.segmented)` | `VADGate` へ渡す preset |

## Reset Settings

| 項目名（日本語） | 親項目 | 項目ID | ラベル | データ仕様 | 発現条件 | 表示仕様 | 異常系の考え方 |
|---|---|---|---|---|---|---|---|
| 設定リセットボタン | `settings-reset` | `reset-all-settings-button` | `Reset All Settings` | Action | 常時 | destructive button | グループ、参加者、credential は変更しない |
| 設定リセット補足文 | `settings-reset` | `reset-all-settings-footer` | 補足文 | 固定文字列 | 常時 | footer | データ削除と混同させない |
