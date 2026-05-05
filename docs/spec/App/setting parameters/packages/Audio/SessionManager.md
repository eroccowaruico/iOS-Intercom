# SessionManager package 設定値

## 目的

本書は、作り直す RideIntercom App が `SessionManager` package へ渡す固定値、導出値、runtime report の扱いを定義する。

画面から直接設定する値は `docs/spec/App/setting parameters/App/設定値一覧.md` を正とし、`SessionManager` の型、既定値、OS差分、operation report、runtime event は `docs/spec/packages/Audio/SessionManager.md` を正とする。

## AudioSessionConfiguration

| package 設定 | App から渡す値 | 種別 | Diagnostics で確認する値 |
|---|---|---|---|
| `mode` | Settings の `Mode` から導出。`Burst mode` は `.default`、`Stream mode` は `.voiceChat` | 画面設定から導出 | resolved mode |
| `defaultToSpeaker` | `Use Speaker == true` または `selectedOutputDevice == .builtInSpeaker` | 画面設定から導出 | requested / resolved output |
| `prefersEchoCancelledInput` | `mode == .default && (Echo Cancellation == true || defaultToSpeaker == true)` | 画面設定から導出 | echo cancellation operation result |
| `preferredInput` | `selectedInputDevice` | 画面設定 | requested / current input |
| `preferredOutput` | `selectedOutputDevice` | 画面設定 | requested / current output |

既定は `Burst mode` + `Use Speaker = false` + `Echo Cancellation = true` とし、Duck Other Audio も opt-in ON から開始する。`voiceChat + prefersEchoCancelledInput` は不正な組み合わせのため UI に出さない。`defaultToSpeaker = true` は speaker 出力向けのため、`mode == .default` では `prefersEchoCancelledInput = true` も同時に要求する。`mode == .voiceChat` では明示的な `prefersEchoCancelledInput` を使わない。

| UI 状態 | `mode` | `defaultToSpeaker` | `prefersEchoCancelledInput` |
|---|---|---:|---:|
| `Burst mode` + `Use Speaker = false` + `Echo Cancellation = false` | `.default` | `false` | `false` |
| `Burst mode` + `Use Speaker = false` + `Echo Cancellation = true` | `.default` | `false` | `true` |
| `Burst mode` + `Use Speaker = true` | `.default` | `true` | `true` |
| `Stream mode` + `Use Speaker = false` | `.voiceChat` | `false` | `false` |
| `Stream mode` + `Use Speaker = true` | `.voiceChat` | `true` | `false` |

## AudioInputStreamConfiguration

| package 設定 | App から渡す値 | 種別 | Diagnostics で確認する値 |
|---|---|---|---|
| `format.sampleRate` | `16_000` | 固定 | input stream snapshot format |
| `format.channelCount` | `1` | 固定 | input stream snapshot format |
| `bufferFrameCount` | `128` | 固定 | start operation report |
| `voiceProcessing` | `AudioInputVoiceProcessingConfiguration` の導出値 | 画面設定と再生状態から導出 | input stream snapshot `inputVoiceProcessing` |

入力 stream の初期適用、未開始時更新、実行中更新はすべて `AudioInputStreamCapture.updateVoiceProcessing(_:)` と `start()` の report/event で確認する。App は `AudioInputVoiceProcessingManager` や `AVAudioInputNode` を保持しない。

## AudioInputVoiceProcessingConfiguration

| package 設定 | App から渡す値 | 種別 | Diagnostics で確認する値 |
|---|---|---|---|
| `soundIsolationEnabled` | `false` | 固定 | requested / applied / ignored |
| `otherAudioDuckingEnabled` | `isDuckOthersEnabled && isOtherAudioDuckingActive` | 画面設定と出力状態から導出 | requested / effective |
| `duckingLevel` | `isOtherAudioDuckingActive ? .normal : .minimum` | 導出 | requested level |
| `inputMuted` | `isMuted` | 画面設定から導出 | requested mute |

Voice Isolation Effect の画面設定は `SoundIsolation` effect の有効/無効であり、SessionManager の `AudioInputVoiceProcessingConfiguration.soundIsolationEnabled` へは渡さない。SessionManager の voice processing は Duck Other Audio とローカルマイクミュートの適用先として使う。

`isOtherAudioDuckingActive` は次をすべて満たす場合だけ `true` とする。

| 条件 |
|---|
| `isDuckOthersEnabled == true` |
| Audio Check 中ではない |
| 直近に可聴な受信音声を最終出力へ渡している |
| `isOutputMuted == false` |
| `masterOutputVolume > 0` |
| 該当 peer の出力音量が 0 ではない |

## AudioOutputStreamConfiguration

| package 設定 | App から渡す値 | 種別 | Diagnostics で確認する値 |
|---|---|---|---|
| `format.sampleRate` | `16_000` | 固定 | output stream snapshot format |
| `format.channelCount` | `1` | 固定 | output stream snapshot format |

出力 renderer の `start()`、`schedule(_:)`、`stop()` は `AudioStreamOperationReport` と `AudioStreamRuntimeEvent` を Diagnostics に集約する。

## Runtime report / event の App 側処理

| Event / report | App の扱い | UI 反映 | ログ |
|---|---|---|---|
| `AudioSessionConfigurationReport` | 直近の session 設定結果として保持 | Diagnostics の Session 行 | `audio.session.configured` |
| `AudioSessionOperationReport.result.applied` | 成功として記録 | 通常状態 | 必要に応じて debug |
| `AudioSessionOperationReport.result.ignored` | 継続可能な環境差異として記録 | Diagnostics に `Ignored` と理由を表示 | debug または notice |
| `AudioSessionOperationReport.result.failed` | media 開始可否へ反映 | Call の音声エラー、Diagnostics に失敗理由 | warning または error |
| `AudioStreamOperationReport` | 入力/出力 stream の直近操作として保持 | Diagnostics の Stream 行 | `audio.stream.operation` |
| `AudioStreamRuntimeEvent.inputFrame` | 入力 level と VAD へ渡す | Call / Settings の入力メーター | 高頻度通常ログは禁止 |
| `AudioStreamRuntimeEvent.outputFrameScheduled` | 最終出力 level と schedule count へ渡す | Call / Settings / Diagnostics の出力メーター | 高頻度通常ログは禁止 |
| `AudioSessionSnapshotChange` | device list / current route を更新 | Settings の picker、Diagnostics の Route 行 | `audio.session.route_changed` |

## App 画面に出さない値

| 値 | 扱い |
|---|---|
| iOS category / mode / options | package 仕様を正とし、App 画面では個別設定しない |
| CoreAudio device 切替の詳細 | `AudioSessionDeviceSelection` と report だけを扱う |
| advanced ducking の OS API 詳細 | `AudioInputVoiceProcessingConfiguration` と stream report だけを扱う |
| voice processing bypass | `soundIsolationEnabled = false` と `otherAudioDuckingEnabled` から package が導出する |
| `AudioInputVoiceProcessingManager` | App は直接保持しない |

詳細な OS 差分と内部既定値は `docs/spec/packages/Audio/SessionManager.md` を正とする。
