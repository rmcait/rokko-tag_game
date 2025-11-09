# API定義書

## 1. 概要
- 対象アプリ: 位置情報ベースの鬼ごっこゲーム (Flutter + Firebase)
- ベースURL: `https://api.tag-game.example.com/v1`
- 認可: Firebase Authentication (Google Sign-In)。全エンドポイントは `Authorization: Bearer <Firebase ID token>` を必須とする。
- 役割: `TAGGER`(鬼) / `RUNNER`(逃亡者)。ゲーム開始時にサーバが割り当てる。
- 共通レスポンス: `traceId` を含め、エラーは RFC7807 互換の `type`, `title`, `status`, `detail`, `instance` を返す。

## 2. リソース別仕様

### 2.1 Users
#### `POST /users`
- Firebase ID token をサーバ側で検証し、初回アクセス時にユーザをプロビジョニング。
- Body
  ```json
  {
    "fcmToken": "string",          // 任意: Push 通知登録
    "displayName": "string",       // 任意: 上書きしたい場合のみ
    "avatarUrl": "https://..."
  }
  ```
- 201 Created:
  ```json
  {
    "userId": "usr_xxx",
    "googleUid": "firebaseUid",
    "displayName": "Rio",
    "avatarUrl": "...",
    "status": "ACTIVE"
  }
  ```

#### `GET /users/me`
- 認証済みユーザ情報と現在参加中のパーティ/ゲーム情報を返す。

#### `PATCH /users/me`
- `displayName`, `avatarUrl`, `fcmToken` を更新。

### 2.2 Parties
#### `POST /parties`
- 任意ユーザが最大5人まで参加できる部屋を生成。
- Body
  ```json
  {
    "name": "string",
    "area": {
      "polygon": [
        {"lat": 35.0, "lng": 139.0}, // 4 ピンの緯度経度
        {"lat": 35.0, "lng": 139.1},
        {"lat": 35.1, "lng": 139.1},
        {"lat": 35.1, "lng": 139.0}
      ]
    },
    "durationMinutes": 15,          // 5 | 15 | 30 | 60 のみ
    "visibility": "PUBLIC"          // PUBLIC or PRIVATE (招待コード)
  }
  ```
- レスポンス: partyId, ownerId, `capacityMax = 5`, `itemSeed`.

#### `GET /parties/{partyId}`
- 現在の参加者、空き枠、エリア、ゲームステータス (`WAITING`, `READY`, `IN_PROGRESS`, `FINISHED`) を返す。

#### `POST /parties/{partyId}/join`
- 参加要求。戻り値にはユーザの暫定ロール(未決定状態)が含まれる。
- 409 を返すケース: 満員 / 既にゲーム進行中。

#### `POST /parties/{partyId}/leave`
- `WAITING` 状態では即退出。`IN_PROGRESS` 中は `playerStatus = DISCONNECTED` 扱い。

#### `POST /parties/{partyId}/roles/assign`
- オーナーまたはサーバタイマーが呼び、参加者の 1 名を `TAGGER`、残りを `RUNNER` にランダム割り当て。
- レスポンスに 30 秒スタンバイの `freezeUntil` タイムスタンプを含める。

#### `POST /parties/{partyId}/start`
- 前提: `participantCount >= 2`。サーバは `gameId` を発行し、`gameSessions` にレコードを生成。

### 2.3 Game Sessions
#### `GET /games/{gameId}`
- ゲーム設定、残り時間、現在のアイテム/イベント状態を返却。

#### `POST /games/{gameId}/locations`
- クライアントが 1 秒〜5 秒間隔で現在位置と速度を送信。
  ```json
  {
    "playerId": "gpl_xxx",
    "lat": 35.0,
    "lng": 139.0,
    "speedMps": 1.2,
    "heading": 120
  }
  ```
- サーバは
  - プレイエリア外の場合 `422` を返す
  - 鬼の移動距離から `gauge` を更新し、閾値超過で `listenReady=true`

#### `POST /games/{gameId}/events/tag`
- 鬼が逃亡者をタッチしたときの申告。Body: `runnerId`, `distanceMeters`.
- サーバが 5m 以内 & 双方エリア内 & 鬼がスタンしていないことを検証し、成功時 `runnerStatus=CAUGHT` とし全員にイベント配信。

#### `POST /games/{gameId}/abilities/listen`
- 鬼専用。条件: `gauge >= threshold` & `cooldownElapsed`.
- Body: `durationSeconds` (サーバが 3〜5 秒に丸める)。
- 成功時レスポンスに `visibleRunners` 配列 (現在位置) を含める。

#### `POST /games/{gameId}/abilities/fake-location`
- 役割共通。Body: `fakeLat`, `fakeLng`, `ttlSeconds`.

#### `POST /games/{gameId}/abilities/freeze-tagger`
- 逃亡者専用。条件: 鬼との距離 ≤5m, アイテム所持, クールダウン未中。
- 成功レスポンス例:
  ```json
  { "effect": "TAGGER_FROZEN", "durationSeconds": 3 }
  ```

#### `POST /games/{gameId}/abilities/trap-trigger`
- 鬼が設置したトラップの発動通知。Body: `itemId`, `runnerId`.

#### `POST /games/{gameId}/abilities/freeze-all`
- 鬼専用。全員の `movementState` を一定時間 `PAUSED` に変更。

### 2.4 Items
#### `GET /games/{gameId}/items`
- 役割別に可視アイテムを返す。レスポンス例
  ```json
  {
    "items": [
      {
        "itemId": "itm_x",
        "type": "SEE_TAGGER",
        "lat": 35.0,
        "lng": 139.0,
        "visibility": "RUNNER"
      }
    ]
  }
  ```

#### `POST /games/{gameId}/items/{itemId}/pickup`
- サーバが所持状態と使用回数 (`stackable`) を更新。アイテムに応じて該当アビリティ API をコール。

### 2.5 Telemetry & Sync
#### `GET /games/{gameId}/sync`
- クライアント再接続時に最新状態を一括取得。`players`, `items`, `gauge`, `cooldowns`, `caughtRunners`, `remainingTime`.

#### WebSocket `/ws/games/{gameId}`
- 双方向イベント通知。種類:
  - `PLAYER_JOINED`, `PLAYER_LEFT`
  - `ROLE_ASSIGNED`
  - `GAME_STARTED`, `GAME_FINISHED`
  - `ITEM_SPAWNED`, `ITEM_PICKED`
  - `ABILITY_TRIGGERED`
  - `TAG_EVENT`

## 3. パラメータ/バリデーション
- `durationMinutes`: enum `[5, 15, 30, 60]`
- 最大人数: 5 (鬼1 + 逃亡者最大4)。サーバ側で強制。
- プレイエリア: 4頂点の凸多角形。面積下限/上限をメートル単位で検証。
- 位置更新: サンプリング 1〜5 秒。10 秒以上届かない場合は `playerStatus=DISCONNECTED`。
- 鬼スタートディレイ: 30 秒 (`freezeUntil` フィールド)。
- リッスンゲージ: 距離 20m あたり 1 ポイント、必要 5 ポイント (例)。サーバで閾値管理。

## 4. エラーレスポンス例
```json
{
  "type": "https://api.tag-game.example.com/errors/party-full",
  "title": "Party is full",
  "status": 409,
  "detail": "partyId par_123 has already 5 players",
  "traceId": "a1b2c3"
}
```

## 5. 将来拡張メモ
- AI モデレータによるチート検出 (スピード違反)。
- パーティの観戦モード API (`GET /games/{gameId}/spectator`).
- 履歴取得 (`GET /users/me/history`) でリザルトを表示。
