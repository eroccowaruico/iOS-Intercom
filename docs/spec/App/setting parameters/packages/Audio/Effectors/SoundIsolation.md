# SoundIsolation package 設定値

## 目的

本書は RideIntercom App が `SoundIsolation` package へ渡す設定値を定義する。

画面から直接設定する値は `docs/spec/App/setting parameters/App/設定値一覧.md` を正とし、本書では固定値、導出値、package adapter が決める値だけを扱う。

## VoiceIsolationConfiguration

| package 設定 | App から渡す値 | 種別 |
|---|---|---|
| `VoiceIsolationConfiguration` | package default | 固定 |
| effect chain 挿入 | App adapter の固定構成で決める | adapter 導出 |

Sound Isolation の画面設定は、原則として `SessionManager` の input voice processing へ渡す。`SoundIsolation` effect を mixer chain に挿入する場合も、mix などの Audio Unit parameter は画面設定にしない。

## App 画面に出さない値

| 値 | 扱い |
|---|---|
| wet / dry mix | package default |
| Audio Unit parameter | package 仕様を正とする |
| support check / fallback | package adapter で扱う |

詳細な SoundIsolation の仕様は `docs/spec/packages/Audio/Effectors/SoundIsolation.md` を正とする。
