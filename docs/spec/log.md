# RideIntercom ログ・保守・運用仕様

## 目的

本書は現行実装で観測できる診断情報、OS ログ出力、運用時の見方を定義する。  
背景、方針、表示意味、異常系の扱いを明示し、Diagnostics 画面と Unified Logging を往復して状態を追跡できるようにする。

## 背景と基本方針

| 項目 | 方針 |
|---|---|
| 背景 | 通話不良は「接続できない」だけでなく、codec 不整合、受信途絶、再生未達など複数段階で起こる |
| 通話継続 | codec フォールバックや受信 drop では通話全体を止めない |
| 観測性 | UI の Diagnostics と Unified Logging の両方で同じ事象を追えるようにする |
| 収集性 | リリース後も `log show` / `log stream` で取得できる形式を維持する |
| 安定性 | ログ記録失敗を理由に例外送出やクラッシュを起こさない |

## 監視対象

| 項目 | 保持値 | 用途 | 意味 |
|---|---|---|---|
| 送信フォールバック累積 | `transmitFallbackCount` | アプリ要求 codec と実際の media codec が一致しない、または fallback 理由が付与された回数 | 送信安全性の累積指標 |
| 最新送信フォールバック | `lastTransmitFallbackSummary` | 最新事象の要約表示 | 直近事象の意味説明 |
| 受信サマリ | `lastReceivedAudioAt`, `droppedAudioPacketCount`, `jitterQueuedFrameCount` | 受信途絶や jitter 蓄積の観測 | 受信系の健全性 |
| 出力サマリ | `lastScheduledOutputRMS`, `scheduledOutputBatchCount`, `scheduledOutputFrameCount` | 再生段まで到達したかの観測 | 出力系の健全性 |

## Diagnostics 画面の表示要件

| セクション | 行 | 表示内容 | 意味・意図 |
|---|---|---|---|
| Live Status | Codec Safety Summary | `TX FB #n / requested->media / reason` | アプリ要求 codec と実際の media codec の差分を追う |
| Live Status | Reception Summary | `LAST RX {sec} / DROP {count} / JIT {count}` | 受信停止、欠落、queue 蓄積を追う |
| Live Status | Playback Summary | `OUT RMS {value} / SCH {count} / FRM {count}` | 実際に再生へ回ったかを追う |
| Live Status | Connection Summary | `PEERS {count}` | peer 数の変化を追う |
| Live Status | Authentication Summary | `AUTH {count}` | 認証成立相手数を追う |
| Identity & Route | Invite Summary | `JOINED ...` / `INVITE READY` / `INVITE NONE` | 招待状態を追う |

## Diagnostics 文言の意味

| 行 | 読み方 |
|---|---|
| Codec Safety Summary | 異常件数だけでなく、最新要約も合わせて「何が起きたか」を読む |
| Reception Summary | 受信が来ていないのか、drop が多いのか、jitter に滞留しているのかを分けて読む |
| Playback Summary | RX が増えていても OUT / SCH / FRM が増えなければ再生段に問題があると読む |
| Connection Summary | 接続 peer 数と認証済み peer 数は別概念として読む |
| Invite Summary | 参加済み、共有可能、招待情報なしを区別して読む |

## Unified Logging

| 項目 | 値 | 意味 |
|---|---|---|
| subsystem | `com.yowamushi-inc.RideIntercom` | アプリ識別子 |
| category | `codec-diagnostics` | codec 系診断ログ分類 |
| logger | `IntercomViewModel.diagnosticsLogger` | 出力責務の中心 |
| level | `error` 相当を中心に利用 | 異常事象を運用取得しやすくする |

### ログイベント

| イベント種別 | 発火条件 | 継続動作 |
|---|---|---|
| TX codec fallback | requested codec と media payload codec が一致しない、または fallback 理由が付与される | 送信は継続する |
| encoder empty payload | 符号化結果が空 payload として扱われる | keepalive 相当として継続する |
| encoding failed | 符号化例外が発生する | keepalive 化または失敗記録後に継続可能性を残す |

### ログ必須フィールド

| ログイベント | 必須フィールド |
|---|---|
| tx fallback | route, streamID, sequenceNumber, requestedCodec, mediaCodec, fallbackReason |

## 取得手順

| 目的 | コマンド例 |
|---|---|
| 直近 1 時間の codec 診断を確認 | `log show --last 1h --predicate 'subsystem == "com.yowamushi-inc.RideIntercom" AND category == "codec-diagnostics"'` |
| リアルタイム監視 | `log stream --predicate 'subsystem == "com.yowamushi-inc.RideIntercom" AND category == "codec-diagnostics"'` |

## 異常時の考え方

| 事象 | 方針 |
|---|---|
| codec フォールバック | 診断対象としつつ通話継続を優先する |
| 受信途絶 | `LAST RX`、drop、jitter、playback を横断して原因を切り分ける |
| ログ未取得 | UI 側 Diagnostics でも同等の事象を追えるようにする |

## 保守観点

| 項目 | 現行仕様 | 意味・意図 |
|---|---|---|
| Diagnostics 文言 | `DiagnosticsSnapshot` で集約生成 | UI 側の読み方を一元化する |
| UI とログの対応 | codec 関連の異常は `codec-diagnostics` と Diagnostics 行の双方で追跡する | 現場確認と詳細追跡を往復可能にする |
| 後方互換性 | Diagnostics 行名とログ category は運用手順と対応するため、変更時はドキュメント同時更新を前提とする | 運用断絶を防ぐ |
| 試験観点 | TX fallback、受信途絶、再生未達の各観測が UI とログの両方で確認できることを重視する | 観測不能化を防ぐ |

## 実装トレーサビリティ

| 領域 | 実装 |
|---|---|
| ログ出力 | `RideIntercom/RideIntercom/IntercomCore.swift` |
| Diagnostics 表示文言 | `RideIntercom/RideIntercom/DiagnosticsSnapshot.swift` |
