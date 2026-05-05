# SoundIsolation package 設定値

## 目的

本書は RideIntercom App が `SoundIsolation` package へ渡す設定値を定義する。

画面から直接設定する値は `docs/spec/App/setting parameters/App/設定値一覧.md` を正とし、本書では固定値、導出値、package adapter が決める値だけを扱う。

## VoiceIsolationConfiguration

| package 設定 | App から渡す値 | 種別 |
|---|---|---|
| `VoiceIsolationConfiguration` | package default | 固定 |
| TX effect chain 挿入 | `isSoundIsolationEnabled && VoiceIsolationSupport.isAvailable` | Settings の送信設定と runtime support から導出 |
| RX peer bus effect chain 挿入 | `remoteSoundIsolationEnabled[peerID, default: false] && VoiceIsolationSupport.isAvailable` | Call の参加者設定と runtime support から導出 |
| RX master bus effect chain 挿入 | `receiveMasterSoundIsolationEnabled && VoiceIsolationSupport.isAvailable` | Call の master 出力設定と runtime support から導出 |

Settings の `Voice Isolation Effect` は送信用 `SoundIsolation` package の effect-level 設定として扱う。Call の参加者行と master 出力行は受信側 peer bus / RX master bus の effect-level 設定として扱う。SessionManager の `AudioInputVoiceProcessingConfiguration.soundIsolationEnabled` へは渡さない。mix などの Audio Unit parameter は画面設定にしない。

| 状態 | App の扱い |
|---|---|
| chain ごとの有効設定が `true` かつ `VoiceIsolationSupport.isAvailable == true` | 該当 bus の effect chain に `VoiceIsolationEffect` を挿入する |
| chain ごとの有効設定が `true` かつ `VoiceIsolationSupport.isAvailable == false` | Toggle を非表示にし、Diagnostics では effect unavailable として扱う |
| chain ごとの有効設定が `false` | 該当 bus の実音声 chain へ挿入しない。runtime chain snapshot では bypassed stage として返し、Diagnostics はその snapshot を表示する |

## App 画面に出さない値

| 値 | 扱い |
|---|---|
| wet / dry mix | package default |
| Audio Unit parameter | package 仕様を正とする |
| support check / fallback の詳細 | package adapter で扱う |

詳細な SoundIsolation の仕様は `docs/spec/packages/Audio/Effectors/SoundIsolation.md` を正とする。
