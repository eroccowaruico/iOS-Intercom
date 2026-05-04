# Codec 仕様

Codec は RideIntercom のアプリ管理音声を、RTC へ渡せる packet payload に変換する Swift Package である。

このライブラリは Float PCM の encode、受信 payload の自動 decode、codec ごとの設定値、transport 可能な frame metadata だけを扱う。マイク取得、ミキシング、Effect chain、RTC 経路選択、暗号化、jitter buffer、WebRTC route-managed media は責務に含めない。

## 目的

| 観点 | 仕様 |
|---|---|
| 主目的 | App が codec 差分を意識せず `PCMCodecFrame -> EncodedCodecFrame`、`EncodedCodecFrame -> PCMCodecFrame` を呼べるようにする |
| 利用箇所 | Mixer に入る前の受信 decode、Mixer 以降または送信直前の encode、RTC packet payload 生成前後 |
| 非目的 | capture / playback device 制御、sample rate 変換、音声品質評価、network packetization、WebRTC native codec negotiation |
| 設計姿勢 | encode は App 設定で codec と codec 固有 option を選ぶ。decode は frame metadata の `codec` を見て自動選択する |

## パッケージ構成

| 項目 | 内容 |
|---|---|
| パス | `RideIntercom/packages/Audio/Codec` |
| Package 名 | `Codec` |
| Product | `Codec` library |
| 対応プラットフォーム | iOS 26.4 以降、macOS 26.4 以降 |
| 使用フレームワーク | `Foundation`, `AVFAudio`, `AudioToolbox` |
| テスト | Swift Testing による SwiftPM テスト |

## 対応 codec

| `CodecIdentifier` | 表示名 | AudioToolbox format | encode | decode | 備考 |
|---|---|---|---|---|---|
| `pcm16` | PCM 16-bit | `kAudioFormatLinearPCM` | 常時対応 | 常時対応 | signed 16-bit little-endian。外部依存なし |
| `mpeg4AACELDv2` | MPEG-4 AAC-ELD v2 | `kAudioFormatMPEG4AAC_ELD_V2` | `AVAudioConverter` が対応する環境で対応 | `AVAudioConverter` が対応する環境で対応 | payload 内に packet description を含める |
| `opus` | Opus | `kAudioFormatOpus` | `AVAudioConverter` が対応する環境で対応 | `AVAudioConverter` が対応する環境で対応 | payload 内に packet description を含める |

`CodecSupport.isEncodingAvailable(for:)` と `CodecSupport.isDecodingAvailable(for:format:)` は現在環境で `AVAudioConverter` が該当 codec を扱えるかを返す。PCM16 は常に `true` を返す。

## 公開 API

| API | 種別 | 役割 |
|---|---|---|
| `AudioCodec` | final class | App が気軽に使うための encode/decode 兼用 facade |
| `CodecEncoder` | final class | `CodecEncodingConfiguration` に従って `PCMCodecFrame` を `EncodedCodecFrame` に変換する |
| `CodecDecoder` | final class | `EncodedCodecFrame.codec` を見て自動 decode する |
| `CodecEncodingConfiguration` | struct | 送信 codec、既定 audio format、AAC/Opus option を保持する |
| `CodecIdentifier` | enum | `pcm16`, `mpeg4AACELDv2`, `opus` を表す |
| `CodecAudioFormat` | struct | sample rate と channel count を表す |
| `PCMCodecFrame` | struct | Float PCM samples と sequence / format / timestamp を持つ |
| `EncodedCodecFrame` | struct | codec、format、timestamp、sample count、transport payload を持つ |
| `PCM16Codec` | enum | PCM16 の純 Swift encode/decode helper |
| `CodecSupport` | enum | codec availability を確認する |
| `CodecError` | enum | codec 不対応、payload 不正、変換失敗などの失敗理由を表す |

## 設定仕様

### `CodecAudioFormat`

| 設定 | 型 | 入力範囲 | 既定値 | 備考 |
|---|---|---|---|---|
| `sampleRate` | `Double` | `8_000...96_000` | `48_000` | 範囲外入力は初期化時に丸める |
| `channelCount` | `Int` | `1...2` | `1` | samples は frame ごとの interleaved 配列として扱う |

`channelCount = 2` の場合、`samples` は `[L0, R0, L1, R1, ...]` の順で渡す。sample 数が channel 数で割り切れない場合、圧縮 codec encode は `CodecError.invalidSampleCount` を返す。

### `CodecEncodingConfiguration`

| 設定 | 型 | 既定値 | 備考 |
|---|---|---|---|
| `codec` | `CodecIdentifier` | `pcm16` | encode 時に使う codec |
| `format` | `CodecAudioFormat` | `48kHz / mono` | `AudioCodec.encode(sequenceNumber:samples:)` の既定 format |
| `aacELDv2Options` | `AACELDv2Options` | `bitRate = 24_000` | `mpeg4AACELDv2` 選択時だけ使う |
| `opusOptions` | `OpusOptions` | `bitRate = 32_000` | `opus` 選択時だけ使う |

| Options | 設定 | 入力範囲 | 既定値 |
|---|---|---|---|
| `AACELDv2Options` | `bitRate` | `12_000...128_000` | `24_000` |
| `OpusOptions` | `bitRate` | `6_000...128_000` | `32_000` |

## Encode / Decode 仕様

| 処理 | 仕様 |
|---|---|
| PCM encode | Float sample を `-1.0...1.0` に丸め、signed 16-bit little-endian の `Data` にする |
| PCM decode | byte 数が偶数であることを検証し、signed 16-bit little-endian から Float PCM に戻す |
| AAC / Opus encode | Float32 PCM の `AVAudioPCMBuffer` を `AVAudioConverter` で compressed buffer に変換する |
| AAC / Opus decode | payload 内の packet description と compressed bytes を使い `AVAudioConverter` で Float32 PCM に戻す |
| Decode 自動選択 | `EncodedCodecFrame.codec` を見て codec を選ぶ。decoder 側に送信設定は渡さない |
| 空 samples | PCM は空 `Data`、AAC / Opus は空 payload envelope として扱い、decode 結果は空 samples になる |

AAC / Opus の payload は raw compressed bytes だけではなく、`AVAudioCompressedBuffer` の packet description、packet count、元の sample count を含む opaque `Data` である。RTC や保存層は `EncodedCodecFrame.payload` をそのまま transport し、内容を解釈しない。

## 接続例

### 送信側

```swift
import Codec

let codec = AudioCodec(
    configuration: CodecEncodingConfiguration(
        codec: .pcm16,
        format: CodecAudioFormat(sampleRate: 48_000, channelCount: 1)
    )
)

let encoded = try codec.encode(
    sequenceNumber: nextSequenceNumber,
    samples: mixedSamples
)

// RTC 側 envelope には encoded.codec / encoded.format / encoded.payload を渡す。
```

### 受信側

```swift
import Codec

let decoder = CodecDecoder()
let decoded = try decoder.decode(encodedFrameFromRTC)

// decoded.samples を Mixer または playback queue に渡す。
```

### codec availability による fallback

```swift
let requested = CodecEncodingConfiguration(codec: .opus)
let configuration = CodecSupport.isEncodingAvailable(for: requested)
    ? requested
    : CodecEncodingConfiguration(codec: .pcm16)

let codec = AudioCodec(configuration: configuration)
```

## RTC との境界

| 項目 | Codec 側 | RTC 側 |
|---|---|---|
| codec 選択 | `CodecEncodingConfiguration.codec` | route policy や signaling で許可 codec を決める |
| payload 生成 | `EncodedCodecFrame.payload` | packet envelope に格納して送る |
| payload 解釈 | `CodecDecoder` | transport では opaque `Data` として扱う |
| sequence / timestamp | `PCMCodecFrame` / `EncodedCodecFrame` に保持 | RTC の envelope と対応付ける |
| 暗号化 / 重複排除 | 対象外 | RTC package 側の責務 |

WebRTC が route-managed media を持つ場合、App 管理 packet audio は RTC 側で送らない。Codec は app-managed packet audio 経路でのみ使う。

## エラー仕様

| Error | 発生条件 | 呼び出し側の扱い |
|---|---|---|
| `invalidSampleCount` | samples 数が channel 数で割り切れない | capture / mixer adapter の frame 生成を修正する |
| `invalidByteCount` | PCM16 payload の byte 数が奇数 | packet 破損として破棄する |
| `invalidFormat` | `AVAudioFormat` を作れない format | App の format 設定を見直す |
| `unsupportedCodec` | ライブラリ未定義 codec を扱おうとした | codec policy を修正する |
| `encoderUnavailable` | 現在環境で該当 codec の encoder を生成できない | PCM16 へ fallback する |
| `decoderUnavailable` | 現在環境で該当 codec の decoder を生成できない | 受信 frame を破棄し、diagnostics に残す |
| `audioFormatCreationFailed` | compressed / PCM format 生成に失敗 | codec と format の組み合わせを見直す |
| `conversionFailed` | `AVAudioConverter` が変換 error を返した | frame を破棄し、必要なら codec fallback する |
| `malformedPayload` | AAC / Opus payload envelope を decode できない | packet 破損または互換性不一致として破棄する |

## 制約と注意点

| 観点 | 内容 |
|---|---|
| sample rate 変換 | 行わない。入力 PCM と `CodecAudioFormat` は一致している前提 |
| channel layout | mono / stereo の interleaved samples のみ扱う |
| AAC / Opus availability | OS、SDK、実行環境の AudioConverter 実装に依存する。利用前に `CodecSupport` を確認する |
| payload 互換性 | AAC / Opus payload は Codec package 専用 envelope であり、外部 decoder へ raw bytes として直接渡さない |
| 低遅延性 | frame size、bit rate、codec の実遅延は統合経路で実測する |
| WebRTC native codec | WebRTC route-managed media の codec negotiation は RTC / WebRTC 側の責務 |

## テスト仕様

| テスト観点 | 確認内容 |
|---|---|
| codec identifier | PCM16 / AAC-ELD v2 / Opus が期待する AudioToolbox format ID を持つ |
| default configuration | PCM16 / 48kHz / mono / AAC 24kbps / Opus 32kbps になっている |
| format 正規化 | sample rate と channel count が範囲内へ丸められる |
| option 正規化 | AAC / Opus の bit rate が範囲内へ丸められる |
| PCM16 encode | signed little-endian、clamp、round-trip を検証する |
| PCM16 decode | 奇数 byte payload を拒否する |
| frame metadata | sequence、format、timestamp、sample count、payload が保持される |
| decode 自動選択 | `EncodedCodecFrame.codec` を見て PCM decode できる |
| compressed payload validation | AAC / Opus で Codec envelope ではない payload を拒否する |
| support | PCM16 は encode / decode とも常に available として返る |

実 AudioConverter による AAC / Opus の音質、遅延、環境差は単体テストでは固定しない。統合テストまたは実機検証で、利用環境ごとの availability と品質を確認する。
