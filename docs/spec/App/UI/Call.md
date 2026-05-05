# RideIntercom Call 画面項目

## 目的

本書は Call タブの UI 項目を定義する。

Call は通話開始、接続維持、参加者確認、入出力の最小操作を行う主画面である。

## グループ選択画面

### 親セクション

| 項目名（日本語） | 項目ID | 目的 | 実装 | 発現条件 | 表示仕様 |
|---|---|---|---|---|---|
| グループ選択画面 | `call-groups-screen` | 接続対象グループを選ぶ起点を提供する | `GroupSelectionView` | `selectedGroup == nil` | `navigationTitle("Groups")` |
| 最近のグループ一覧 | `call-groups-list` | 過去に保持したグループを一覧表示する | `List > Section("Recent Groups")` | `selectedGroup == nil` | グループ一覧の親コンテナ |
| グループ選択ツールバー | `call-groups-toolbar` | 新しいグループを作成する | `ToolbarItem(placement: .primaryAction)` | `selectedGroup == nil` | 右上に新規作成ボタン |

### 子項目

| 項目名（日本語） | 親項目 | 項目ID | ラベル | データ仕様 | 表示仕様 | 異常系の考え方 |
|---|---|---|---|---|---|---|
| 空状態メッセージ | `call-groups-list` | `groups-empty-message` | `Create a group to start a call.` | 固定文字列 | カード風表示 | データ不足をエラー扱いしない |
| グループ行 | `call-groups-list` | `group-row` | グループ名 | `IntercomGroup` | 行全体タップで選択 | 選択だけでは既存接続を奪わない |
| グループアイコン | `group-row` | `group-row-icon` | なし | `activeGroupID == group.id` | `person.3`。接続中は success 色 | 選択中だけでは強調しない |
| グループ名 | `group-row` | `group-row-name` | `group.name` | `String` | 最大 2 行 | 空表示にしない |
| メンバー数 | `group-row` | `group-row-member-count` | `"{n} members"` | `Int` | 補助テキスト | 接続中人数ではなく保存メンバー数 |
| 遷移インジケーター | `group-row` | `group-row-disclosure` | なし | 固定 SF Symbol | `chevron.right` | なし |
| スワイプ削除 | `group-row` | `group-row-swipe-delete` | `Delete` | 対象 `group.id` | 破壊操作 | フルスワイプ不可 |
| コンテキスト削除 | `group-row` | `group-row-context-delete` | `Delete` | 対象 `group.id` | context menu | swipe と同一意味 |
| グループ作成ボタン | `call-groups-toolbar` | `create-group-button` | `Create Talk Group` | Action | 右上ボタン | 押下で `Talk Group` を作成して選択 |

## 通話画面

### 親セクション

| 項目名（日本語） | 項目ID | 目的 | 実装 | 発現条件 | 表示仕様 |
|---|---|---|---|---|---|
| 通話画面 | `call-screen` | 接続、音声入出力、参加者状態を一画面で扱う | `CallView` | `selectedGroup != nil` | 画面タイトルは `selectedGroup.name` |
| 通話ツールバー | `call-toolbar` | グループ一覧へ戻る導線 | toolbar | 常時 | 左上に `Groups` |
| 通話ステータスヘッダー | `call-status-header` | 通話全体の状態を最上部に集約する | `statusHeader` | 常時 | 接続、入力、出力をまとめる |
| 接続/招待操作領域 | `call-primary-controls` | 主要操作をまとめる | `controls` | 常時 | 横幅に応じて横並びまたは縦並び |
| 参加者セクション | `call-participants-section` | 相手ごとの状態、出力調整、peer bus effect 設定を扱う | `VStack` | 常時 | 見出しと参加者領域 |
| 音声エラー表示領域 | `call-error-section` | 音声系失敗を可視化する | `Text` | `audioErrorMessage != nil` | 赤文字 |

### ステータスヘッダー

| 項目名（日本語） | 親項目 | 項目ID | ラベル | データ仕様 | 表示仕様 | 状態 |
|---|---|---|---|---|---|---|
| 通話状態要約 | `call-status-header` | `call-connection-summary` | `Call status` | `callPresenceLabel`, `routeLabel`, `connectionState`, `isAudioReady` | 接続アイコン + 2 行テキスト | Idle、Waiting、Connected / Audio Idle、通話中 |
| 接続状態ラベル | `call-connection-summary` | `call-presence-label` | 接続状態名 | `String` | 1 行目 | 状態不明時も文言化する |
| 経路ラベル | `call-connection-summary` | `call-route-label` | 経路 | `String` | 2 行目補助テキスト | Local / Internet / Offline / Control Only |
| ローカル入力ヘッダー | `call-status-header` | `local-microphone-header` | `Input` | `GroupMember`, `Bool` | ローカル入力状態カード | Live / Muted |
| ローカル入力メーター | `local-microphone-header` | `local-microphone-meter` | なし | `voiceLevel`, `voicePeakLevel`, `isMuted` | 値文字列なしのメーター | 入力レベルとピーク |
| ローカルミュートボタン | `local-microphone-header` | `local-microphone-mute-button` | `Mute` / `Unmute` | `Bool` | アイコン付きボタン | 押下でマイクミュート反転 |
| マスター出力グループ | `call-status-header` | `master-output-group` | `Output` | `masterOutputVolume`, `isOutputMuted`, `receiveMasterSoundIsolationEnabled` | 出力ラベル + スライダー + Voice Isolation + ミュート | OS 音量ではなく App 最終出力 |
| マスター出力スライダー | `master-output-group` | `master-output-slider` | `Output Volume` | `Float`, `0...2` | `1.0` が通常、`1.0` 超過は boost | 過大時は最終サンプルをソフトクリップ |
| マスター出力 Voice Isolation Effect | `master-output-group` | `master-output-voice-isolation-toggle` | `Voice Isolation` | `receiveMasterSoundIsolationEnabled`。既定 `false` | `supportsSoundIsolation == true` のとき Toggle | RX master bus の SoundIsolation effect 有効/無効 |
| マスター出力ミュートボタン | `master-output-group` | `master-output-mute-button` | `Mute Output` / `Unmute Output` | `Bool` | ミュート時は赤系 | 入力や接続は止めない |
| ダッキング状態アイコン | `master-output-group` | `call-ducking-status-icon` | なし | `isDuckOthersEnabled`, `isOtherAudioDuckingActive` | 設定 ON 時のみ `waveform` | 設定 ON と実効 ON を分ける |

### 接続/招待操作

| 項目名（日本語） | 親項目 | 項目ID | ラベル | データ仕様 | 表示仕様 | 異常系の考え方 |
|---|---|---|---|---|---|---|
| グループ一覧戻りボタン | `call-toolbar` | `show-groups-button` | `Groups` | Action | 左上ボタン | 接続は維持する |
| 接続切替ボタン | `call-primary-controls` | `connect-disconnect-button` | `Connect` / `Disconnect` | 接続状態依存 | 主要ボタン | 音声起動失敗と接続失敗を分ける |
| 招待ボタン | `call-primary-controls` | `invite-button` | `Invite` | `selectedGroupInviteURL` | `ShareLink` | URL が作れない場合は表示しない |

## 参加者

| 項目名（日本語） | 親項目 | 項目ID | ラベル | データ仕様 | 表示仕様 | 状態 |
|---|---|---|---|---|---|---|
| 参加者見出し | `call-participants-section` | `participants-title` | `Participants` | 固定文字列 | セクション見出し | なし |
| 参加者空状態 | `call-participants-section` | `participants-empty` | `No remote riders` | 固定文字列 | 空状態カード | 相手不在 |
| 参加者カード行 | `call-participants-section` | `remote-participant-row` | 参加者カード | `GroupMember`, `remoteOutputVolumes[member.id]`, `remoteSoundIsolationEnabled[member.id]` | 1 参加者 1 カード | 受信音声がなくても存在 |
| 参加者名 | `remote-participant-row` | `participant-name` | `member.displayName` | `String` | 最大 2 行 | 保存名 |
| 接続/認証アイコン | `remote-participant-row` | `participant-status-icons` | なし | `connectionState`, `authenticationState` | Wi-Fi 系 + 認証系 | 接続軸と認証軸を分ける |
| コーデック表示 | `remote-participant-row` | `participant-codec-label` | `PCM 16-bit` など | `AudioCodecIdentifier?` | `Label`。未観測は `--` | 最後に観測した codec |
| 参加者入力メーター | `remote-participant-row` | `participant-input-meter` | なし | `voiceLevel`, `voicePeakLevel`, `isMuted` | 値文字列なし | 受信後デコード済みレベル |
| 参加者出力スライダー | `remote-participant-row` | `participant-output-slider` | `{name} Output` | `Double`, `0...1`。未設定時 `1.0` | 個別出力スライダー | マスター出力とは別。peer bus volume へ即時反映 |
| 参加者 Voice Isolation Effect | `remote-participant-row` | `participant-voice-isolation-toggle` | `Voice Isolation` | `remoteSoundIsolationEnabled[member.id]`。未設定時 `false` | `supportsSoundIsolation == true` のとき Toggle | 該当 peer bus の SoundIsolation effect 有効/無効 |
| 参加者削除 | `remote-participant-row` | `participant-swipe-delete` / `participant-context-delete` | `Delete` | 対象 `member.id` | swipe / context menu | ローカルメンバーは対象外 |

## エラー表示

| 項目名（日本語） | 親項目 | 項目ID | ラベル | データ仕様 | 表示仕様 | 異常系の考え方 |
|---|---|---|---|---|---|---|
| 音声エラーメッセージ | `call-error-section` | `audio-error-message` | 音声エラー文言 | `String` | 赤色フットノート | 画面全体を塞がず、その場で読める補助文言として扱う |
