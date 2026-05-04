# RideIntercom App 状況確認仕様

## 目的

本書は、RideIntercom App の画面上でユーザーが確認できる状態と、その読み方だけを定義する。

本書では画面に表示される状態のみを扱う。

## 対象画面

| 画面 | 確認すること |
|---|---|
| Call | 通話先、接続状態、音声入出力、参加者状態、招待可否 |
| Diagnostics | 通話、送受信、再生、認証、経路の要約状態 |
| Settings | 入出力デバイス、音声設定、Audio Check の状態 |

画面項目の詳細な配置、ラベル、表示条件は `docs/spec/App/UI/画面項目定義.md` を正とする。

## Call 画面で確認する状態

| 表示 | 読み方 |
|---|---|
| グループ名 | 現在表示している通話対象グループ |
| 接続状態 | 未接続、接続準備中、接続済み、通話可能、再接続中、失敗を確認する |
| 経路表示 | Local / Internet / Offline など、現在使っている、または試行している経路 |
| Connect / Disconnect | 接続開始できる状態か、既に接続中で切断操作になる状態かを確認する |
| Invite | 招待 URL を共有できる状態かを確認する |
| 入力状態 | 自分のマイクが Live か Muted かを確認する |
| 入力メーター | 自分の声がアプリへ入っているかを確認する |
| 出力状態 | 受信音声のマスター音量と出力ミュートを確認する |
| 他音声ダック状態 | 設定 ON と実際の発動中を区別して確認する |
| 参加者カード | 相手ごとの接続、認証、入力レベル、出力音量を確認する |
| エラー表示 | マイク権限、音声起動、入出力デバイス変更などの失敗理由を確認する |

## Diagnostics 画面で確認する状態

Diagnostics は、通常画面だけでは分かりにくい状態を要約して確認するための画面とする。

| 表示 | 読み方 |
|---|---|
| Call Summary | 接続状態と音声準備状態をまとめて確認する |
| Reception Summary | 最終受信、drop、jitter queue の状態を確認する |
| Audio Summary | TX、RX、PLAY の進み方を比較する |
| Playback Summary | 受信音声が最終出力へ渡っているかを確認する |
| Codec Safety Summary | codec fallback の有無と直近内容を確認する |
| Connection Summary | 通信上の peer 数を確認する |
| Authentication Summary | 音声受理可能な認証済み peer 数を確認する |
| Local Network Summary | Local 経路の待受、接続、拒否などの状態を確認する |
| Invite Summary | 招待済み、招待可能、招待情報なしを確認する |

Diagnostics の値は画面上の状態確認用として扱う。

## Settings 画面で確認する状態

| 表示 | 読み方 |
|---|---|
| 入力デバイス | どの入力を使う設定になっているかを確認する |
| 出力デバイス | どの出力を使う設定になっているかを確認する |
| Sound Isolation | 入力処理の有効/無効を確認する |
| Duck Other Audio | 他アプリ音声を下げる設定の有効/無効を確認する |
| VAD 感度 | 発話判定の感度設定を確認する |
| Audio Check | マイク録音とスピーカー再生の確認状態を確認する |
| Reset | App の画面設定を初期値へ戻す操作を確認する |

設定値の正本は `docs/spec/App/setting parameters/App/設定値一覧.md` とする。

## Audio Check で確認する状態

| 状態 | 読み方 |
|---|---|
| recording | マイク入力を取得している |
| playing | 録音した音声を再生している |
| completed | 入力と出力の確認が完了した |
| failed | 権限、入力なし、再生失敗などにより確認できなかった |

Audio Check は通話中の品質評価ではなく、端末の入力と出力が使えるかを画面上で確認する機能とする。

## 状態確認時の考え方

| 状況 | 確認する画面 |
|---|---|
| 相手につながらない | Call の接続状態、Diagnostics の Connection / Authentication |
| 自分の声が届かない | Call の入力状態と入力メーター、Settings の入力デバイス |
| 相手の声が聞こえない | Call の参加者入力、出力状態、Diagnostics の Reception / Playback |
| 音が小さい | Call のマスター出力音量、参加者別出力音量 |
| マイクが使えない | Call のエラー表示、Settings の入力デバイス、Audio Check |
| 招待できない | Call の Invite 表示、Diagnostics の Invite Summary |

本書では、画面で何を確認するかだけを扱う。
