# DB定義書

## 1. データストア構成
- Firebase Authentication: Google Sign-In で `uid` を発行。
- Firestore (Native モード) をメイン DB とし、リアルタイム同期に活用。
- Cloud Storage: アバター等のバイナリ管理。I(アイコンの画像ファイル, アプリ内の音声ファイルなど)
- Cloud Functions: ゲームロジック/整合性チェック。

## 2. コレクション設計

### 2.1 `users`
| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `userId` | string | PK | `usr_` で始まるアプリ内ID |
| `googleUid` | string | Y | Firebase Auth UID |
| `displayName` | string | Y | 端末からの上書き可 |
| `avatarUrl` | string | N | Cloud Storage の署名付きURL |
| `status` | string | Y | `ACTIVE`, `BANNED`, `DELETED` |
| `fcmToken` | string | N | Push 通知用 |
| `createdAt` | timestamp | Y | |
| `updatedAt` | timestamp | Y | |

複合インデックス: `status` + `updatedAt desc` (オンラインユーザ検索)。

### 2.2 `parties`
| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `partyId` | string | PK | `par_` プレフィックス |
| `ownerId` | string | Y | `users/{userId}` リンク |
| `name` | string | Y | |
| `capacityMax` | number | Y | 常に 5 |
| `status` | string | Y | `WAITING`, `READY`, `IN_PROGRESS`, `FINISHED`, `CANCELLED` |
| `durationMinutes` | number | Y | 5/15/30/60 |
| `area.polygon` | array<object> | Y | 4 つの `{lat, lng}` |
| `visibility` | string | Y | `PUBLIC`, `PRIVATE` |
| `inviteCode` | string | N | PRIVATE 時のみ |
| `gameId` | string | N | 進行中ゲームへの参照 |
| `itemSeed` | string | Y | アイテム配置乱数 |
| `createdAt`, `updatedAt` | timestamp | Y | |

サブコレクション: `parties/{partyId}/members`
| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `memberId` | string | PK | `mem_` |
| `userId` | string | Y | |
| `role` | string | N | `TAGGER`, `RUNNER` (未割り当ては `PENDING`) |
| `order` | number | N | UI 並び順 |
| `ready` | bool | Y | |
| `joinedAt` | timestamp | Y | |

複合インデックス: `userId` + `status` (参加中のパーティ検索)。

### 2.3 `gameSessions`
| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `gameId` | string | PK | `gam_` |
| `partyId` | string | Y | |
| `status` | string | Y | `PREPARE`, `ACTIVE`, `ENDED`, `ABORTED` |
| `startAt` | timestamp | Y | |
| `endAt` | timestamp | N | |
| `freezeUntil` | timestamp | Y | 鬼の30秒スタート遅延 |
| `durationMinutes` | number | Y | |
| `area` | object | Y | パーティ作成時点のコピー |
| `gaugeThreshold` | number | Y | リッスン発動に必要 |
| `listenDurationSeconds` | number | Y | 3〜5 秒 |
| `movementSampleWindow` | number | Y | 距離計算用 (メートル) |
| `winner` | string | N | `TAGGER`, `RUNNER`, `DRAW` |
| `createdAt`, `updatedAt` | timestamp | Y | |

サブコレクション: `gameSessions/{gameId}/players`
| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `playerId` | string | PK | `gpl_` |
| `userId` | string | Y | |
| `role` | string | Y | |
| `status` | string | Y | `ACTIVE`, `CAUGHT`, `DISCONNECTED` |
| `gauge` | number | N | 鬼のみ |
| `cooldowns` | map | N | アビリティ別残り秒 |
| `items` | map | N | 所持アイテムと残回数 |
| `lastLocation` | geopoint | N | 最終測位 |
| `lastUpdateAt` | timestamp | N | 位置送信時刻 |

サブコレクション: `gameSessions/{gameId}/items`
| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `itemId` | string | PK | `itm_` |
| `type` | string | Y | `SEE_TAGGER`, `FAKE_LOCATION`, `FREEZE_TAGGER`, `TRAP`, `FREEZE_ALL` |
| `visibility` | string | Y | `TAGGER` or `RUNNER` |
| `lat`,`lng` | number | Y | |
| `spawnedAt` | timestamp | Y | |
| `pickedBy` | string | N | `playerId` |
| `state` | string | Y | `AVAILABLE`, `PICKED`, `USED`, `EXPIRED` |

### 2.4 `gameSessions/{gameId}/events`
時系列ログ。クエリ最適化のため `createdAt` 降順インデックス。
| フィールド | 型 | 説明 |
| --- | --- | --- |
| `eventId` | string | PK (`gev_`) |
| `type` | string | `PLAYER_JOINED`, `LOCATION_UPDATE`, `ITEM_PICKED`, `ABILITY_TRIGGERED`, `TAG`, `SYSTEM` |
| `payload` | map | イベント固有データ |
| `createdAt` | timestamp | |

### 2.5 `telemetry`
- Cloud Functions から BigQuery にエクスポートするための一時領域。
- フィールド例: `gameId`, `playerId`, `metric`, `value`, `recordedAt`.

## 3. 参照・制約
- `parties.ownerId` → `users.userId`
- `parties.members[].userId` → `users.userId`
- `gameSessions.partyId` → `parties.partyId`
- `gameSessions.players[].userId` → `users.userId`
- Firestore ではアプリ側で整合性を担保:
  - パーティ参加数 5 超の場合は Cloud Function トランザクションで拒否。
  - ゲーム中のロール変更は禁止。必要なら次ゲームでのみ再割当。

## 4. 主要ユースケースのデータフロー
1. **サインイン**: Firebase Auth → `users` ドキュメント作成/更新。
2. **パーティ作成**: `parties` + `members(owner)` を atomically 作成。
3. **参加**: `members` に追加し、`parties.status` を `READY` へ遷移 (人数2以上)。
4. **ゲーム開始**: Cloud Function が `gameSessions` + `players` を生成し、`freezeUntil` を30秒後に設定。
5. **位置送信**: Realtime Database/Firestore いずれかで受信 → Functions が移動距離を積算して `players.gauge` を更新。
6. **アイテム出現**: `gameSessions/{gameId}/items` に乱数シード基づき書き込み。Visibility でクライアント表示を制御。
7. **能力発動**: 該当フィールド (`items`, `cooldowns`, `events`) をトランザクションで更新。

> **参加要件メモ**: オンラインユーザ（アプリをインストールして会員登録済み、または招待リンク経由で会員登録したユーザ）のみが、ホストが作成したパーティに ID を入力して参加できる。未登録ユーザはパーティ参加 API に到達できない。

## 5. インデックス方針
- `parties`: `status` + `updatedAt desc` (ロビー表示)
- `parties/members`: `userId` + `joinedAt desc` (参加履歴)
- `gameSessions`: `status` + `updatedAt desc` (現在進行ゲーム検索)
- `gameSessions/{gameId}/players`: `status` + `role`
- `gameSessions/{gameId}/events`: `createdAt desc`

## 6. データ保持とクリーンアップ
- ゲーム終了後 30 日で `gameSessions` と子コレクションを Cloud Task で削除 (BigQuery へサマリ移送済みであることが前提)。
- 退会ユーザ (`status=DELETED`) は個人情報を匿名化し、過去ゲームの統計のみ保持。

## 7. セキュリティルール要点
- ユーザは `users/{userId}` 自身のみ read/write。
- `parties`: `ownerId` が write、参加者は read + `/members/{userId}` 自分の `ready` フラグのみ更新可。
- `gameSessions`: 参加者のみ read。書き込みは Cloud Functions 経由 (位置更新は特定エンドポイント)。
- アイテム/アビリティはサーバ署名 (`serverTimestamp`) 付きで検証し、クライアント改竄を防止。
