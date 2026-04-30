# PeakLimiter 仕様

PeakLimiter は Apple 標準の `AUPeakLimiter` Audio Unit を、RideIntercom の音声パイプラインから再利用しやすい Swift Package として切り出したエフェクトライブラリである。

このライブラリはマイク入力、受信音声、ミキサー出力など任意の `AVAudioEngine` ノードチェーンに差し込めるピーク保護エフェクトだけを扱う。音声ルーティング、通信、コーデック、録音、再生デバイス制御は責務に含めない。

## 目的

| 観点 | 仕様 |
|---|---|
| 主目的 | `kAudioUnitSubType_PeakLimiter` を `AVAudioUnitEffect` として生成し、任意の `AVAudioEngine` グラフに挿入できるようにする |
| 体験上の目的 | 突発的なピークを抑え、EQやコンプレッサー後のクリップを防ぎ、耳に痛い破綻を避ける |
| 利用箇所 | DynamicsProcessor後、EQ後、ミキサー出力前、受信音声再生前など、呼び出し側が選んだ位置 |
| 非目的 | 音量差をならす主処理、ノイズ除去、Audio Session 管理、通信経路への組み込み、音声仕様全体の変更 |
| 設計姿勢 | Audio Unit の存在確認、声用途の初期設定、設定値の正規化、パラメータ適用だけを薄く包む |

## パッケージ構成

| 項目 | 内容 |
|---|---|
| パス | `RideIntercom/Effectors/PeakLimiter` |
| Package 名 | `PeakLimiter` |
| Product | `PeakLimiter` library |
| 対応プラットフォーム | iOS 17 以降、macOS 14 以降 |
| 使用フレームワーク | `AVFAudio`, `AudioToolbox` |
| テスト | Swift Testing による SwiftPM テスト |

## 公開API

| API | 種別 | 役割 |
|---|---|---|
| `PeakLimiterSupport` | enum | `AUPeakLimiter` の `AudioComponentDescription` と利用可否を提供する |
| `PeakLimiterConfiguration` | struct | リミッターの設定値を保持する |
| `PeakLimiterEffect` | final class | `AVAudioUnitEffect` を生成し、設定を Audio Unit parameter に適用する |
| `PeakLimiterError` | enum | 生成不可、パラメータ欠落などの失敗理由を表す |

## Audio Unit 定義

| Audio Unit 属性 | 値 |
|---|---|
| componentType | `kAudioUnitType_Effect` |
| componentSubType | `kAudioUnitSubType_PeakLimiter` |
| componentManufacturer | `kAudioUnitManufacturer_Apple` |
| componentFlags | `0` |
| componentFlagsMask | `0` |

`PeakLimiterSupport.isAvailable` は `AudioComponentFindNext` で現在の実行環境に `AUPeakLimiter` が存在するか確認する。呼び出し側はこの値を見て、設定UIの有効化やフォールバック経路の選択を行う。

## 設定仕様

| 設定 | 型 | 入力範囲 | Audio Unit へ渡す値 | 既定値 | 備考 |
|---|---|---|---|---|---|
| `attackTime` | `Float` | `0.001...0.03` sec | `kLimiterParam_AttackTime` | `0.012` | ピークへ反応する速さ。短すぎる不自然さを避ける |
| `decayTime` | `Float` | `0.001...0.06` sec | `kLimiterParam_DecayTime` | `0.024` | 抑制後に戻る速さ |
| `preGain` | `Float` | `-40...40` dB | `kLimiterParam_PreGain` | `0` | リミッター前の入力ゲイン。初期値では音量を持ち上げない |

範囲外入力は `PeakLimiterConfiguration` の初期化時に上表の範囲へ丸める。

## 生成と適用

| 処理 | 仕様 |
|---|---|
| 生成 | `PeakLimiterEffect.make(configuration:)` が `AUPeakLimiter` の存在確認後に `AVAudioUnitEffect.instantiate` で生成する |
| ノード取得 | `PeakLimiterEffect.node` で `AVAudioNode` として取得する |
| 詳細アクセス | `PeakLimiterEffect.avAudioUnitEffect` で `AVAudioUnitEffect` として取得する |
| 設定適用 | `PeakLimiterEffect.apply(_:)` が Audio Unit parameter tree に各設定値を設定する |
| 設定保持 | 適用成功時のみ `configuration` を更新する |
| 失敗時 | Audio Unit がない、生成に失敗した、必要な parameter がない場合に throw する |

## 接続例

| ユースケース | ノード接続 |
|---|---|
| DynamicsProcessor後の最終保護 | `DynamicsProcessorEffect.node -> PeakLimiterEffect.node -> Mixer` |
| EQ後のクリップ防止 | `EQ -> PeakLimiterEffect.node -> Mixer` |
| 受信音声の突発ピーク保護 | `PlayerNode -> PeakLimiterEffect.node -> Mixer` |
| 出力直前の安全弁 | `Mixer -> PeakLimiterEffect.node -> OutputNode` |

```swift
import AVFAudio
import PeakLimiter

let engine = AVAudioEngine()
let player = AVAudioPlayerNode()
let limiter = try await PeakLimiterEffect.make(
    configuration: PeakLimiterConfiguration()
)

engine.attach(player)
engine.attach(limiter.avAudioUnitEffect)
engine.connect(player, to: limiter.node, format: format)
engine.connect(limiter.node, to: engine.mainMixerNode, format: format)
```

## エラー仕様

| Error | 発生条件 | 呼び出し側の扱い |
|---|---|---|
| `audioUnitUnavailable` | `AudioComponentFindNext` で `AUPeakLimiter` が見つからない | エフェクトなしの経路へフォールバックする |
| `instantiationFailed` | `AVAudioUnitEffect.instantiate` が Audio Unit を返さない | ログへ失敗理由を残し、エフェクトなしの経路へフォールバックする |
| `missingParameter` | Audio Unit parameter tree に必要な parameter が存在しない | Audio Unit の互換性問題として扱い、エフェクトなしの経路へフォールバックする |

## 制約と注意点

| 観点 | 内容 |
|---|---|
| 用途 | ピーク保護を目的とし、音量差をならす主処理には DynamicsProcessor を使う |
| preGain | 音量を上げる目的で強く使うと常時リミットされて不自然になるため、初期値は `0` とする |
| 配置 | クリップ防止のため、EQやDynamicsProcessorなど音量を変えるエフェクトの後段に置くことを基本にする |
| ライブラリ責務 | フォールバック音声経路の構築、UI表示、診断ログ、音声品質評価は呼び出し側で行う |

## テスト仕様

| テスト観点 | 確認内容 |
|---|---|
| Audio Unit descriptor | Apple の `AUPeakLimiter` effect を指す定数になっている |
| 既定値 | RideIntercom の声用途初期設定になっている |
| 値の正規化 | 各設定値が定義範囲に丸められる |

実 Audio Unit の存在や音質は実行環境に依存するため、単体テストでは設定値と descriptor の正しさを検証する。実機やOS差を含む音声品質評価は、このライブラリを呼び出す統合経路側で扱う。
