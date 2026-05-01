# セッションマネージャー

mac と iOSの音声入出力を一手に解決する。

やること。
出力はデフォルト以外も含めて指定できるようにする。
マイクもデフォルト以外も含めて指定できるようにする。

アプリからみたI/Fは抽象化され統一されており、設定値以外でOSの区別がないこと。

ただし、iOSはOSの範囲内で全体の最適解を見つけながら開発する。そのあたりの内容は以下。

## iOS基本指針
duckOthers　を利用するのは会話が電話のような会話をしない前提。
push2talkではないもののそれに近いぐらい無線的な使い方。

ただし会話をもっと楽しみたい場合はvoiceChatを利用する。
enableAdvancedDucking と tureにして、利用すること。

ここを設定を分けてセッションをコントロールできるようにする。

## カテゴリ
playAndRecord 固定


## カテゴリオプション
### 対応可能な時は必ずON
static var allowBluetoothA2DP
static var allowBluetoothHFP
static var bluetoothHighQualityRecording
static var duckOthers
static var farFieldInput
static var mixWithOthers

### アプリから渡した時のみON
static var defaultToSpeaker

### その他
static var overrideMutedMicrophoneInterruption　絶対に停止してはいけない。

## モード
### 基本
default

### アプリから指示があった場合のみ


voiceChat ただし他のアプリの音声が一度切れる。レシーバーを利用したい場合のみ。エコーキャンセルが発動してスピーカー出力の構成が変わる。

## echo cancellation (モードがデフォルトの場合のみ)

アプリから指示があった場合のみ。モードがデフォルトの場合のみアプリからOnOFF設定させる。ただし他のアプリの音声が一度切れる。エコーキャンセルが発動してスピーカー出力の構成が変わる。
voiceChatとこちらはスピーカーとの利用などで使い分け。

setPrefersEchoCancelledInput



