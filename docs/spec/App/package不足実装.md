# App 側に暫定で残る package 不足実装

## 目的

本書は、App 本体から package へ寄せたいが、現時点では package 側の公開 API が不足しているため App 側に暫定で残す実装を記録する。

`docs/spec/packages` は変更せず、今後 package 側を拡張する時の入力として扱う。

## 不足している実装

| package | 不足している実装 | 現在の暫定場所 | App から消す条件 |
|---|---|---|---|
| SessionManager | iOS / macOS の入出力デバイス変更通知を package イベントとして受け取る API | `RideIntercom/Platform/Audio/SystemAudioSessionAdapter.swift` | App が OS 別の route change / CoreAudio listener を持たず、SessionManager の snapshot 更新通知だけを見る |
| Audio package | マイク入力 capture とスピーカー出力 renderer の共通抽象 | `RideIntercom/Platform/Audio/SystemAudioInputMonitor.swift`、`RideIntercom/Platform/Audio/SystemAudioOutputRenderer.swift` | App が AVAudioEngine の入力 tap / 出力 player node を直接扱わない |
| RTC | 受信音声 frame の jitter、重複排除、順序制御を App から使える公開 API | `RideIntercom/Intercom/Audio/AudioPackets.swift` の `JitterBuffer` | RTC が受信済み音声を再生可能な順序とタイミングで渡す |
| AudioMixer | decode 済み PCM frame を peer 別音量と master 音量でまとめる軽量 API | `RideIntercom/Intercom/Audio/AudioPackets.swift` の `AudioFrameMixer`、`IntercomViewModel+AudioOutput.swift` | App が sample 配列を直接 mix / clamp しない |

## 方針

App 側の暫定実装は UI 状態へつなぐための薄い境界に留める。package 側に同等の公開 API が追加されたら、App 側の重複実装を削除する。
