# SessionManager 仕様

## 目的

`SessionManager` は RideIntercom の音声入出力セッションと入力ノード側の voice processing を、アプリから統一的に制御する Swift Package とする。アプリは iOS / macOS の差を直接扱わず、共通の設定型とsnapshotだけでセッション、入出力デバイス、advanced ducking、入力ミュートを扱う。
本パッケージがOS差異の全て吸収する。アプリは全く同じ処理をOSの区別なく呼び出すことが可能になる。本パッケージは呼び出されたOS固有処理を無視して取り扱うことが可能。

アプリ本体への組み込みは本仕様の対象外とする。この package は単体で build / test でき、将来アプリから呼び出すだけで使えるライブラリとして成立させる。

## 採用方針

| 項目 | 方針 |
|---|---|
| package名 | `SessionManager` |
| 最低サポートOS | iOS `26.4`、macOS `26.4` |
| session category | iOS は `playAndRecord` 固定 |
| session mode | 標準は `default`。アプリが明示した場合のみ `voiceChat` を使う |
| category options | iOSで利用可能な通話向けoptionを標準で有効にする |
| echo cancellation | `mode == default` の場合のみ `setPrefersEchoCancelledInput` を適用する |
| advanced ducking | `AVAudioInputNode.voiceProcessingOtherAudioDuckingConfiguration` を `AudioInputVoiceProcessingManager` から制御する |
| マイクミュート | 入力エンジンを止めず `isVoiceProcessingInputMuted` でミュートする |
| device selection | アプリからは入力/出力とも `AudioSessionDeviceSelection` で指定する |
| OS差分 | `SystemAudioSessionBackend` と `SystemAudioInputVoiceProcessingBackend` に閉じ込め、非対応OSで呼ばれたOS固有操作は成功扱いのno-opにする |
| テスト | fake backendで設定解決、呼び出し順序、advanced ducking、ミュートを検証し、実マイク/実スピーカーへ依存しない |

## 公開API

| 型 | 役割 |
|---|---|
| `AudioSessionManager` | category / mode / options、入力/出力選択、active切替、snapshot取得を行う facade |
| `AudioInputVoiceProcessingManager` | input node の voice processing、advanced ducking、入力ミュートを行う facade |
| `AudioSessionConfiguration` | アプリから渡すsession希望設定。mode、speaker既定、echo cancellation、入力/出力選択を持つ |
| `AudioInputVoiceProcessingConfiguration` | アプリから渡すinput node希望設定。sound isolation、other audio ducking、ducking level、入力ミュートを持つ |
| `ResolvedAudioSessionConfiguration` | OSへ適用するsession確定設定。category、mode、category options、echo cancellation適用可否を持つ |
| `AudioSessionDevice` | 入力/出力デバイスを表す共通モデル |
| `AudioSessionDeviceSelection` | system default、built-in speaker、built-in receiver、device ID指定を表す |
| `AudioSessionSnapshot` | 利用可能な入力/出力、現在の入力/出力、active状態を返す |
| `AudioSessionBackend` | session制御のテスト/OS差し替え用backend境界 |
| `AudioInputVoiceProcessingBackend` | input node制御のテスト/OS差し替え用backend境界 |
| `SystemAudioSessionBackend` | iOSでは `AVAudioSession`、macOSではCoreAudio default deviceを扱う標準backend |
| `SystemAudioInputVoiceProcessingBackend` | 全OSで同じ初期化と操作を持つ標準backend。iOSでは `AVAudioInputNode` 注入時だけ適用し、macOSまたは未注入時はno-opにする |

## OS差分の扱い

| 操作 | iOS | macOS | アプリ側の扱い |
|---|---|---|---|
| session category / mode / options | `AVAudioSession` へ適用する | no-op | 同じ `AudioSessionConfiguration` を渡す |
| session active切替 | `AVAudioSession.setActive` へ適用する | no-op | 接続開始/終了で同じ `setActive` を呼ぶ |
| `prefersEchoCancelledInput` | `setPrefersEchoCancelledInput` へ適用する | no-op | mode制約だけ守り、OS分岐しない |
| built-in speaker / receiver出力 | `overrideOutputAudioPort` へ適用する | no-op | iOS向け指定をmacOSで呼んでも失敗しない |
| CoreAudio device ID入力 | 利用可能入力IDと一致する場合だけ適用する | default input deviceへ適用する | 共通の `.device(id)` を使う |
| CoreAudio device ID出力 | no-op | default output deviceへ適用する | macOS向け指定をiOSで呼んでも失敗しない |
| voice processing / advanced ducking / input mute | `AVAudioInputNode` 注入時だけ適用する | no-op | `SystemAudioInputVoiceProcessingBackend(inputNode:)` または空初期化を同じように使う |

補足: no-opは「そのOSに対応する実体がない操作を失敗にしない」ための扱いである。指定したdevice IDがそのOSで実際に適用対象になる場合に見つからないときは、設定ミスを隠さず `deviceNotFound` を返す。

## Session設定マトリクス

| `AudioSessionConfiguration` | category | mode | category options | `setPrefersEchoCancelledInput` | 用途 |
|---|---|---|---|---|---|
| 既定 | `playAndRecord` | `default` | 標準ON options | `false` | 無線的な会話、音楽併用、接続中も他アプリ音声を極力保つ |
| `defaultToSpeaker = true` | `playAndRecord` | `default` | 標準ON options + `defaultToSpeaker` | 設定値通り | スピーカーを既定出力にしたい場合 |
| `prefersEchoCancelledInput = true` | `playAndRecord` | `default` | 標準ON options | `true` | `voiceChat` ではなくdefault modeのままecho cancellationだけ使いたい場合 |
| `mode = voiceChat` | `playAndRecord` | `voiceChat` | 標準ON options、必要なら `defaultToSpeaker` | 適用しない | 電話に近い会話体験やレシーバー利用を優先する場合 |
| `mode = voiceChat` かつ `prefersEchoCancelledInput = true` | 適用しない | 適用しない | 適用しない | 適用しない | 不正。`echoCancelledInputRequiresDefaultMode` をthrowする |

## iOS Category Options

| option | 既定 | 追加条件 | 対応するOS API | 制約 |
|---|---:|---|---|---|
| `allowBluetoothA2DP` | ON | なし | `AVAudioSession.CategoryOptions.allowBluetoothA2DP` | `playAndRecord` でA2DP出力候補を許可する |
| `allowBluetoothHFP` | ON | なし | `AVAudioSession.CategoryOptions.allowBluetoothHFP` | HFP入力候補を許可する |
| `bluetoothHighQualityRecording` | ON | なし | `AVAudioSession.CategoryOptions.bluetoothHighQualityRecording` | 対応routeでのみ有効。非対応routeではOSが無視する |
| `duckOthers` | ON | なし | `AVAudioSession.CategoryOptions.duckOthers` | session active中のカテゴリoption。細かい強度制御はinput node側advanced duckingで行う |
| `farFieldInput` | ON | なし | `AVAudioSession.CategoryOptions.farFieldInput` | `allowBluetoothHFP` が必要なため常に同時ONにする |
| `mixWithOthers` | ON | なし | `AVAudioSession.CategoryOptions.mixWithOthers` | 他アプリ音声との共存を標準にする |
| `overrideMutedMicrophoneInterruption` | ON | なし | `AVAudioSession.CategoryOptions.overrideMutedMicrophoneInterruption` | ハードウェアミュート時もセッションを停止させない |
| `defaultToSpeaker` | OFF | `defaultToSpeaker = true` | `AVAudioSession.CategoryOptions.defaultToSpeaker` | レシーバーではなくスピーカーを既定にしたい用途だけで使う |

## Voice Processing設定マトリクス

| `AudioInputVoiceProcessingConfiguration` | `setVoiceProcessingEnabled` | `enableAdvancedDucking` | `duckingLevel` | `isVoiceProcessingBypassed` | `isVoiceProcessingInputMuted` | 意味 |
|---|---:|---:|---|---:|---:|---|
| 既定 | `true` | `true` | `.min` | `false` | `false` | sound isolationを使い、other audio duckingの影響は最小にする |
| `soundIsolationEnabled = true`, `otherAudioDuckingEnabled = true`, `duckingLevel = .normal` | `true` | `true` | `.default` | `false` | 設定値通り | sound isolationと通常強度duckingを併用する |
| `soundIsolationEnabled = false`, `otherAudioDuckingEnabled = true`, `duckingLevel = .normal` | `true` | `true` | `.default` | `true` | 設定値通り | uplink処理はbypassし、advanced duckingだけ維持する |
| `soundIsolationEnabled = true`, `otherAudioDuckingEnabled = false` | `true` | `true` | `.min` | `false` | 設定値通り | sound isolationだけ使い、duckingの影響は最小にする |
| `soundIsolationEnabled = false`, `otherAudioDuckingEnabled = false` | `false` | `false` | `.min` | 適用しない | 設定値通り | voice processingを使わないが、入力ミュート状態は反映する |
| `inputMuted = true` | 他設定に従う | 他設定に従う | 他設定に従う | 他設定に従う | `true` | 入力エンジンは止めず、OSのvoice processing input muteだけを有効にする |

補足: `enableAdvancedDucking` は `otherAudioDuckingEnabled` のON/OFFにかかわらず、voice processingが有効な間は `true` を使う。OFF時は `duckingLevel = .min` にして、接続中やマイク常時ONの副作用を最小にする。

補足: `isVoiceProcessingBypassed = true` は、duckingだけ必要でsound isolationを使わない状態を表す。voice processing自体はducking APIのためにONのまま維持する。

補足: `inputMuted = true` は録音停止ではない。入力ノード、voice processing、advanced duckingの更新先を維持したまま、入力サンプルだけをミュートする。

## mode と Echo Cancellation

| mode | session側echo cancellation | input node側voice processing | 制約 |
|---|---|---|---|
| `default` | `prefersEchoCancelledInput` を `setPrefersEchoCancelledInput` へ渡す | `AudioInputVoiceProcessingConfiguration` に従う | echo cancellation preferenceを明示できる |
| `voiceChat` | 明示的な `setPrefersEchoCancelledInput` は使わない | `AudioInputVoiceProcessingConfiguration` に従う | `prefersEchoCancelledInput = true` との同時指定は禁止 |

補足: `voiceChat` は他アプリ音声や出力経路へ大きく影響する可能性があるため、アプリが明示した場合だけ使う。

補足: `setPrefersEchoCancelledInput` と `AVAudioInputNode.setVoiceProcessingEnabled` は別の適用点である。SessionManagerは両方を扱うが、session設定とinput node設定を別managerに分け、再構成タイミングをアプリが制御できるようにする。

## 入出力デバイス選択

| platform | 入力選択 | 出力選択 | 制約 |
|---|---|---|---|
| iOS | `availableInputs` にある `AVAudioSessionPortDescription.uid` を `AudioSessionDevice.ID` として指定できる | system default、built-in speaker、built-in receiverを指定できる。任意device出力指定はno-op | Bluetooth/AirPlay等の外部出力はOS route selectionに従う。任意外部出力を直接選ぶAPIは提供しない |
| macOS | CoreAudio device IDを指定して default input device を変更できる。built-in speaker / receiver入力指定はno-op | CoreAudio device IDを指定して default output device を変更できる。built-in speaker / receiver出力指定はno-op | default device変更として作用する。アプリ専用routeではない |

## 適用順序

| 対象 | 順序 | 操作 | 理由 |
|---|---:|---|---|
| session | 1 | `AudioSessionConfiguration.resolved()` | 不正な組み合わせをOSへ渡す前に検出する |
| session | 2 | `backend.apply(resolved)` | category / mode / optionsを確定する |
| session | 3 | `backend.setPreferredInput(...)` | category適用後に入力route希望を渡す |
| session | 4 | `backend.setPreferredOutput(...)` | category適用後に出力route希望を渡す |
| session | 5 | `backend.setPrefersEchoCancelledInput(...)` | default modeのときだけecho cancellation希望を反映する |
| session | 6 | `setActive(true)` | アプリがmedia開始するタイミングで明示的にactive化する |
| input node | 1 | `setVoiceProcessingEnabled(...)` | sound isolationまたはadvanced duckingが必要な時だけONにする |
| input node | 2 | `setAdvancedDucking(enabled:level:)` | voice processingが有効な間にadvanced duckingを設定する |
| input node | 3 | `setVoiceProcessingBypassed(...)` | sound isolationだけをbypassし、duckingだけ維持する状態を作る |
| input node | 4 | `setInputMuted(...)` | 入力を止めずにミュート状態だけ反映する |

補足: `AudioSessionManager.configure` はactive化しない。接続準備や設定画面で呼んでも、実際のmedia開始までは `setActive(true)` を呼ばない。

補足: マイクはmedia中に常時ONの入力ノードとして維持する。ミュート切替、ducking level切替、sound isolation切替は入力ノードを停止せず、可能な限りプロパティ更新で反映する。

## Snapshot

| フィールド | 意味 |
|---|---|
| `isActive` | backendが見ているactive状態または利用中状態 |
| `availableInputs` | `systemDefaultInput` とOSから取得した入力候補 |
| `availableOutputs` | `systemDefaultOutput` とOSで指定可能な出力候補 |
| `currentInput` | 現在の入力route |
| `currentOutput` | 現在の出力route |

## エラー

| エラー | 発生条件 |
|---|---|
| `echoCancelledInputRequiresDefaultMode` | `voiceChat` と `prefersEchoCancelledInput = true` を同時指定した |
| `inputSelectionUnsupported` | 実行OSで入力として成立しないselectionを、no-op対象ではない文脈で指定した |
| `outputSelectionUnsupported` | 実行OSで出力として成立しないselectionを、no-op対象ではない文脈で指定した |
| `deviceNotFound` | 指定device IDがOSの候補にない、またはmacOS device IDとして解釈できない |
| `coreAudioOperationFailed` | macOS CoreAudio default device切替が失敗した |

## 利用例

```swift
import AVFAudio
import SessionManager

let sessionManager = AudioSessionManager()
try sessionManager.configure(
    AudioSessionConfiguration(
        mode: .default,
        defaultToSpeaker: true,
        prefersEchoCancelledInput: true,
        preferredInput: .systemDefault,
        preferredOutput: .builtInSpeaker
    )
)
try sessionManager.setActive(true)

let inputManager = AudioInputVoiceProcessingManager(
    backend: SystemAudioInputVoiceProcessingBackend(inputNode: audioEngine.inputNode)
)
try inputManager.configure(
    AudioInputVoiceProcessingConfiguration(
        soundIsolationEnabled: true,
        otherAudioDuckingEnabled: true,
        duckingLevel: .normal,
        inputMuted: false
    )
)
```

マイクミュート時は入力エンジンを停止しない。

```swift
try inputManager.setInputMuted(true)
```

`voiceChat` を使う場合は echo cancellation preference を同時指定しない。

```swift
try sessionManager.configure(
    AudioSessionConfiguration(
        mode: .voiceChat,
        defaultToSpeaker: false,
        prefersEchoCancelledInput: false
    )
)
```

## テスト方針

| テスト | 検証内容 |
|---|---|
| default configuration | 標準option、category、mode、echo cancellation既定値 |
| defaultToSpeaker | 明示時のみoptionが追加されること |
| voiceChat | echo cancellation preferenceを適用しないこと |
| invalid echo cancellation | `voiceChat` と明示echo cancellationの同時指定を拒否すること |
| manager apply order | category適用、入力、出力、echo cancellation、activeの順序 |
| system default devices | system defaultへ戻すselectionがbackendへ渡ること |
| snapshot | backendの状態をアプリ向けsnapshotとして返すこと |
| advanced ducking | input node側で `enableAdvancedDucking = true` とducking levelを適用すること |
| input mute | 入力停止ではなく `setInputMuted` として反映すること |
