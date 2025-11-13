# Copilot Instructions for tag_game

## プロジェクト概要
Flutter 3.35.7 (Dart 3.9系) を使用した、**リアルタイムオンライン鬼ごっこゲーム**のMVPアプリケーション。Firebase統合のサーバーレス構成で、位置情報共有・捕獲判定・ゲームロジックを実装。fvmでFlutterバージョン管理を行い、iOS/Android両プラットフォームに対応。

### ゲーム仕様
- **ルール**: 鬼1人 vs 逃走者最大4人、制限時間内（5分/15分/30分/1時間）に全員捕獲で鬼勝利
- **位置共有**: 5秒間隔でFirestoreへ座標送信、リアルタイムマップ表示（Google Maps API）
- **捕獲判定**: Cloud Functionsで距離計算（< 2m）、自動的に `status: "caught"` 更新
- **アイテムシステム**: 鬼/逃走者別のアイテム（位置可視化、一時停止、偽情報、トラップ等）

## 開発ワークフロー

### 必須：fvmプレフィックス
このプロジェクトでは全てのFlutterコマンドに`fvm`プレフィックスが必要です。直接`flutter`コマンドを実行しないこと。

```bash
# ✓ 正しい
fvm flutter run
fvm flutter test
fvm flutter pub get

# ✗ 間違い
flutter run
```

### Makefileベースの開発フロー
開発タスクは`Makefile`で標準化されています。直接flutterコマンドではなくmakeターゲットを使用：

- **初期セットアップ**: `make init` - Flutter SDK取得、依存関係インストール、OS判定してエミュレータ起動
- **iOS実行** (macOS): `make run-ios` - iPhone 17 Proシミュレータで起動
- **Android実行**: `make run-android` - Pixel 8エミュレータ（emulator-5554）で起動
- **テスト**: `make test`
- **ビルド**: `make build` - Android APK + iOS同時ビルド
- **クリーン**: `make clean`

### OS固有の動作
````instructions
# Copilot instructions — tag_game (concise)

Short goal: help contributors make small, correct edits quickly. Focus on where code lives, how to run things, and project constraints.

- Key entry points: `lib/main.dart`, `lib/app.dart`, `lib/firebase_options.dart` (auto-generated — do not edit).
- Project layout to reference: `lib/core/`, `lib/data/` (models, services, repository), `lib/presentation/` (pages + matching `*_viewmodel.dart`), and `functions/` (Cloud Functions).

- Always use the Makefile and fvm-prefixed Flutter: prefer `make init`, `make run-android`, `make run-ios`, `make test`, `make build`. Do not run `flutter` directly; use `fvm flutter ...` if needed.

- Firebase notes: config files (`firebase_options.dart`, `google-services.json`, `GoogleService-Info.plist`) are committed. Avoid running `flutterfire configure` unless instructed. Cloud Functions live under `functions/src` and implement capture logic.

- Common patterns to follow (examples):
  - Location updates: `lib/data/services/location_service.dart` uses a 5s Timer that writes to `players/{playerId}` in Firestore. Keep update frequency and schema consistent.
  - View/ViewModel pairing: pages have `page.dart` + `viewmodel.dart` next to each other in `presentation/pages/*`.
  - Data access: go through `lib/data/repository.dart` or services in `lib/data/services/` — do not access Firestore directly from widgets.

- Tests: use `make test` / `fvm flutter test`. To test UI without Firebase, use `MyApp(firebaseReady: false)` (see `test/widget_test.dart`). Use `fake_cloud_firestore` and mock `GeolocatorPlatform` for data-layer tests.

- Environment quirks: `Makefile` may select devices by name (e.g., `iPhone 17 Pro`, `emulator-5554`). On Windows, use `make run-android` and update Makefile device flags if your emulator name differs (`make devices` to list).

- When editing: keep to existing project conventions — snake_case filenames, UpperCamelCase for classes, and pair page/viewmodel splits. Add tests for new public functions or viewmodels.

- Quick references (files to open first):
  - `AGENTS.md` (repo guidelines), `README.md` (setup + Makefile targets)
  - `lib/main.dart`, `lib/app.dart`, `lib/data/repository.dart`, `lib/data/services/`, `presentation/pages/game/game_viewmodel.dart`

If anything below is unclear or you want this file to bias more toward tests, refactors, or Cloud Functions, tell me which focus and I'll iterate.

````
│   ├── utils/                  # 距離計算、座標変換、日時フォーマット
