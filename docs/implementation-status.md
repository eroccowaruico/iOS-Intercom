# 実装ステータス

本リポジトリでは、仕様書のフェーズ順に実装を進める。

## Phase 1: Local 2人通話（体験の核）

- Transport抽象とLocal(MC)実装: `Transport` / `LocalTransport`
- オーディオセッション設定: `AudioSessionManager`
- VAD状態機械＋プレロール保持: `VoiceActivityDetector`
- KEEPALIVEはControlMessageの型を用意（送出は上位レイヤーで統合予定）

## Phase 2: Local 6人通話（固定UI）

- UI/ミキサーは今後追加予定。

## Phase 3+: グループ永続化/招待/Internet移行/セキュリティ

- データ永続化、招待トークン、GK transport、暗号化等は今後のフェーズで実装予定。
