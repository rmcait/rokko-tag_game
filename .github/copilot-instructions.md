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
`Makefile`はOS判定（`uname`）を行い、macOSではiOS、それ以外ではAndroidを自動選択します。Windows環境では特にこの動作を理解すること。

## アーキテクチャとパターン

### Firebase統合パターン
`main.dart`ではFirebase初期化が必須：

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp(firebaseReady: true));
}
```

- `lib/firebase_options.dart`は**FlutterFire CLIで自動生成**されたファイル（手動編集禁止）
- `firebase.json`に全プラットフォームの構成が定義済み
- Firebase接続状態はSnackBarで日本語UIフィードバック（`firebase_core: ^4.2.1`使用）

### プロジェクト構造
**クリーンアーキテクチャベース**のディレクトリ構成を採用：
```
lib/
├── main.dart
├── app.dart                    # MaterialApp・ルーティング設定
├── firebase_options.dart       # 自動生成（手動編集禁止）
├── core/
│   ├── theme/                  # ThemeData、カラー定義
│   ├── utils/                  # 距離計算、座標変換、日時フォーマット
│   └── constants/              # 定数（制限時間、捕獲距離、更新間隔等）
├── data/
│   ├── models/                 # Player, GameRoom, Item（Firestore DTO）
│   ├── services/               # Firebase（Firestore/Auth/Functions）、位置情報取得
│   └── repository.dart         # データ取得の統一窓口
├── domain/
│   └── entities.dart           # ビジネスロジック用エンティティ（中長期用・省略可）
└── presentation/
    ├── pages/                  # 画面単位でディレクトリ分割
    │   ├── home/               # ホーム画面
    │   │   ├── home_page.dart
    │   │   └── home_viewmodel.dart
    │   ├── login/              # ログイン画面
    │   ├── lobby/              # ロビー（ルーム作成/参加）
    │   ├── game/               # ゲームプレイ画面（マップ表示）
    │   └── result/             # 結果表示
    ├── widgets/                # 共通ウィジェット（マーカー、ボタン等）
    └── routes.dart             # ルーティング定義
```

**ディレクトリ別の役割**:
- **core/**: フレームワーク非依存のユーティリティ・定数
- **data/**: 外部データソース（Firebase、位置情報API）との通信層
- **domain/**: ビジネスルール（MVP段階では省略可能）
- **presentation/**: UI・ViewModelによる画面構築（MVVM推奨）

**重要ファイル**:
- **test/**: `widget_test.dart`のみ存在。新規テスト追加時も`fvm flutter test`で実行
- **functions/**: Cloud Functions（捕獲判定・ゲーム終了ロジック）は別途セットアップが必要
- **プラットフォーム固有設定**:
  - Android: `android/app/google-services.json`
  - iOS: `ios/Runner/GoogleService-Info.plist`
  - macOS: `macos/Runner/GoogleService-Info.plist`

### コーディング規約
- `analysis_options.yaml`で`package:flutter_lints/flutter.yaml`を適用
- 標準のFlutter lintルールに従う（カスタムルールは未定義）
- 日本語UIテキスト/コメントを許容（`'Firebase に接続しました'`等）

### アーキテクチャパターン
- **MVVM (Model-View-ViewModel)**: 各画面に`*_page.dart`と`*_viewmodel.dart`をペアで作成
- **Repository Pattern**: `data/repository.dart`を通じてFirestore/位置情報サービスにアクセス
- **Dependency Injection**: 将来的に`provider`または`riverpod`導入を推奨
- **ViewModel例**:
  ```dart
  // presentation/pages/game/game_viewmodel.dart
  class GameViewModel extends ChangeNotifier {
    final Repository _repository;
    GameViewModel(this._repository);
    
    void startLocationTracking() {
      _repository.locationService.startUpdates();
    }
  }
  ```

## 重要な制約事項

### デバイス名の環境依存性
`Makefile`内のデバイス指定は開発環境に依存：
- iOS: `"iPhone 17 Pro"` - Xcode設定でiOS 18ランタイムが必要
- Android: `"emulator-5554"` - デフォルトのPixel 8想定

**環境が異なる場合**: `make devices`で利用可能デバイスを確認し、Makefileの`-d`フラグを更新すること。

### Firebase設定の取り扱い
- 既存の`firebase_options.dart`や`google-services.json`は**リポジトリにコミット済み**
- `flutterfire configure`の再実行は不要（既存設定を保護）
- Firebase CLI操作が必要な場合のみ、README.mdの「6. Firebase CLI」セクションを参照

## ゲーム固有のアーキテクチャパターン

### Firestoreデータモデル（推奨構造）
```
/games/{gameId}
  - status: "waiting" | "playing" | "finished"
  - oniPlayerId: string
  - startTime: timestamp
  - duration: 300 | 900 | 1800 | 3600 (秒)
  - players: Map<playerId, {name, role, status, position}>

/players/{playerId}
  - currentGameId: string
  - position: {lat: number, lng: number, timestamp}
  - role: "oni" | "runner"
  - status: "alive" | "caught"
  - lastUpdate: timestamp

/items/{itemId}
  - position: {lat, lng}
  - type: "reveal_oni" | "fake_position" | "freeze_trap" | "stop_all"
  - targetRole: "oni" | "runner"
  - isActive: boolean
```

### リアルタイム位置更新パターン
```dart
// LocationServiceの実装例
class LocationService {
  Timer? _locationTimer;
  
  void startLocationUpdates(String playerId) {
    _locationTimer = Timer.periodic(
      Duration(seconds: 5),
      (_) async {
        final position = await _getCurrentPosition();
        await FirebaseFirestore.instance
          .collection('players')
          .doc(playerId)
          .update({
            'position': {'lat': position.latitude, 'lng': position.longitude},
            'lastUpdate': FieldValue.serverTimestamp(),
          });
      },
    );
  }
}
```

### Cloud Functions統合パターン
捕獲判定はFirestoreトリガーで実装：
```typescript
// functions/src/index.ts (参考)
export const checkCapture = functions.firestore
  .document('players/{playerId}')
  .onUpdate(async (change, context) => {
    const newPosition = change.after.data().position;
    // 距離計算（Haversine formula）
    // if (distance < 2m && role === 'runner') { status = 'caught' }
  });
```

### Google Maps API統合
- **Android**: `android/app/src/main/AndroidManifest.xml`にAPI Key設定
- **iOS**: `ios/Runner/AppDelegate.swift`でGMSServices初期化
- パッケージ: `google_maps_flutter: ^2.x.x` を`pubspec.yaml`に追加予定

### 必要な追加パッケージ（将来的に）
```yaml
dependencies:
  geolocator: ^10.x.x          # 位置情報取得
  google_maps_flutter: ^2.x.x  # 地図表示
  cloud_functions: ^4.x.x      # Functions呼び出し
  rxdart: ^0.27.x              # ストリーム管理（オプション）
```

## テストアプローチ
現在はシンプルなウィジェットテストのみ（`widget_test.dart`）。Firebase依存コンポーネントをテストする際は：
- `MyApp`の`firebaseReady`パラメータでFirebase初期化をモック可能
- `testWidgets`内で`pumpWidget(const MyApp(firebaseReady: false))`を使用してFirebaseなしテスト
- **位置情報テスト**: `geolocator`の`GeolocatorPlatform.instance`をモック
- **Firestoreテスト**: `fake_cloud_firestore`パッケージでローカルテスト可能

## トラブルシューティング
- `flutter doctor`エラー時 → READMEの指示に従いライセンス承諾やSDK追加
- キャッシュ問題 → `make clean`
- 依存関係エラー → `make pub-get`
- ビルドエラー → `fvm flutter clean && fvm flutter pub get`の順で実行
