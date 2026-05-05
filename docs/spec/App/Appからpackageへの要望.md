# App から package への要望と現状の回避

本ドキュメントは解決済みの内容を残さないこと。
パッケージ更新時はこのドキュメントを参照して、App 側で回避している内容が解消されているか確認すること。
パッケージ更新時は本ドキュメントを編集や更新を一切しないこと。

## 目的

本書は、App 側で見つかった package の不足責務だけを記録する。

App を作り直す前提では、App 側の暫定実装や既存コードの棚卸しは本書に残さない。`docs/spec/packages` の仕様で吸収すべき不足が見つかった場合だけ、package 要求として追記する。

## 現在の package 要求

| package | 不足している責務 | App に暫定実装しない理由 | App から消す条件 |
|---|---|---|---|
| SessionManager | `mode == .default` で `defaultToSpeaker = true` の場合、`prefersEchoCancelledInput = true` を package 側で自動的に解決してほしい。speaker 出力は echo cancellation と組で扱うべきで、App がこの結合を毎回補う設計にしたくない | OS 差分吸収と設定受け取りに関わる。App は `Use Speaker` というユーザー希望だけを渡し、SessionManager が default mode の speaker 向け session 設定を一貫して解決するのが責務境界として自然 | `AudioSessionConfiguration.resolved()` または `AudioSessionManager.configure(_:)` が `defaultToSpeaker = true && mode == .default` を受けたときに `prefersEchoCancelledInput = true` を resolved/report に含める。`mode == .voiceChat` では既存通り明示的な `prefersEchoCancelledInput` を適用しない |


パッケージ全体として、docs/spec/App/UI/Diagnostics.md を組む際に必要な情報は全て、App側の設定などで作らせずに、package側でリアルタイムに渡せるようにすること。
また、通話画面などに出す情報やこれからデバッグ用に出す情報としても通信相手のセッション状態や通信設定、コーデック設定、エフェクト設定など設定や操作情報も全てpackage側から渡せるようにすること。（データチャンネルを利用して変更時と接続時と定期的に送信すること）
App側で作るべき情報があるとすれば、package側で必要な設定だけであり、表示用の情報は全てpackage側で渡せるようにすること。
特にmixerの経路や、エフェクトチェーン、RTCの接続状態など、OS差分や継続可能な準異常系の処理も含めて全てをリアルタイムに渡せるようにすること。
受信情報でなければイベントである必要はないが、それ含めて理想的な設計をすること。

## 追記ルール

| 記録する項目 | 内容 |
|---|---|
| package | 変更対象 package |
| 不足している責務 | App ではなく package が持つべき責務 |
| App に暫定実装しない理由 | package 独立性、OS差分吸収、準異常系処理、runtime 情報通知、設定受け取りのどれに関わるか |
| App から消す条件 | どの package API / runtime event / report があれば App が同一呼び出しで使えるか |

## App 作り直し時の扱い

| 項目 | 方針 |
|---|---|
| App 側暫定実装 | 作り直し前の都合として扱い、本書には残さない |
| package に既にある責務 | `docs/spec/packages` と `docs/spec/App/setting parameters/packages` を参照し、App 仕様へ重複定義しない |
| 新しい不足の判断 | App が OS 差分、継続可能な準異常系、runtime report/event、設定受け取りを自前で補う必要が出た場合だけ追記する |
