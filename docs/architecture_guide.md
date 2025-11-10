# Tag Game アーキテクチャ入門

Flutter 初心者が迷わないように、`lib/` 以下を以下の 5 レイヤーに分割しています。  
画面を増やしたり Firebase と通信したりする際は、この動線に沿ってファイルを追加してください。

```
lib/
 ├── main.dart
 ├── app.dart
 ├── core/          基盤コード（テーマ・ユーティリティ・定数）
 ├── data/          API や Firebase など外部データとのやり取り
 ├── domain/        アプリ内部で使う純粋な Entity
 └── presentation/  画面（UI）と ViewModel
```

## 1. 起動の流れ

1. `main.dart` で Firebase を初期化し、`TagGameApp`（`app.dart`）を起動。
2. `TagGameApp` は `core/theme/app_theme.dart` のテーマを適用し、`presentation/routes.dart` に定義したルートを使って画面を切り替えます。
3. 初期表示は `presentation/pages/home/home_page.dart`。ボタンを押すと ViewModel を通じてデータを再取得します。

## 2. Core レイヤー

- `core/theme/app_theme.dart` … 全画面共通の `ThemeData` を定義。
- `core/constants/app_constants.dart` … アプリ名などの定数。
- `core/utils/logger.dart` … デバッグ用ロガー。実案件では Crashlytics 等に差し替え可能。

## 3. Data レイヤー

| ファイル | 役割 |
| --- | --- |
| `data/services/firebase_service.dart` | FirebaseAuth の状態監視など、認証系 SDK との境界。 |
| `data/services/firestore_user_service.dart` | `FirebaseFirestore` を直接握り、`users` コレクションの CRUD を担当。クエリや `FieldValue.serverTimestamp()` など SDK 依存の処理はここで完結させます。 |
| `data/models/user_model.dart` | Firestore ドキュメント（`DocumentSnapshot`）をドメイン層の `UserEntity` に変換。 |
| `data/repository.dart` | ViewModel から呼び出す窓口。Service で取得した `UserModel` を `UserEntity` に変換し、UI からは Firestore の詳細を意識せずに利用できます。 |

## 4. Domain レイヤー

- `domain/entities.dart` には `UserEntity` を定義。  
  UI と Data の依存を絶ち、テストやモックがしやすいようにしています。

## 5. Presentation レイヤー

- `presentation/pages/home` … Home 画面と `HomeViewModel`。`UserRepository` を介してユーザーデータを取得し、`notifyListeners()` で UI を更新します。
- `presentation/pages/login` … ログイン画面の雛形。UI を作りたい場合はここから。
- `presentation/widgets/custom_button.dart` … アプリ共通のボタン。
- `presentation/routes.dart` … 画面パスを一元管理。`AppRoutes.home` など定数で指定。

### ViewModel とデータフロー（Firestore 版）

1. `HomePage` が `HomeViewModel.load()` を呼び出す。
2. `HomeViewModel` が `UserRepository.fetchLatestUserAndTouch()` を実行。
3. `UserRepository` は `FirestoreUserService.fetchSampleUser()` で Firestore からユーザードキュメントを1件取得し、`UserModel` → `UserEntity` へ変換。
4. 同時に `FirestoreUserService.touchUser()` で `updatedAt` に `serverTimestamp` を書き込み、最新アクセスを記録。
5. ViewModel が `notifyListeners()` を呼び、`HomePage` が `UserEntity` を元に UI を描画する。

## 6. Firestore `users` コレクションのデータフロー詳細

Firestore と UI の結線が理解しやすいよう、`users` コレクションを例にコード参照付きでフローを追います。

1. **Firestore からの読み取り**  
   - `lib/data/services/firestore_user_service.dart` の `fetchSampleUser()` が `users` コレクションを `updatedAt` 降順で1件取得します。  
   - Firestore SDK 固有の `QuerySnapshot` や `Timestamp` はこの層で閉じ込めます。

2. **モデル変換**  
   - `lib/data/models/user_model.dart` の `UserModel.fromDoc()` が `DocumentSnapshot` を安全にパースし、`UserEntity` へ変換できる形に整えます。  
   - `Timestamp` は `DateTime` へ、ドキュメント ID は不足時の `userId` として補完します。

3. **Repository での責務分離**  
   - `lib/data/repository.dart` の `UserRepository.fetchLatestUserAndTouch()` が上記サービスを呼び出し、`UserModel.toEntity()` で `UserEntity` を返します。  
   - Firestore 開発者が把握すべき「どのコレクションを触っているか」という情報は Repository までで完結し、ViewModel には露出しません。

4. **UI への受け渡し**  
   - `lib/presentation/pages/home/home_viewmodel.dart` は `UserRepository` を DI し、`load()` で `UserEntity` を取得して `_user` に保持、`notifyListeners()` を実行します。  
   - エラー時や空データ時のハンドリングも ViewModel 内で吸収します。

5. **画面表示**  
   - `lib/presentation/pages/home/home_page.dart` が ViewModel の `user` を監視し、`displayName` や `status`, `updatedAt` を UI に描画。  
   - 「Reload data」ボタンで ViewModel の `load()` を呼べば再度 Firestore～UI までの一連の流れが実行されます。

これらの責務分離により、Firestore SDK の書き換え・Mock 化・Firestore Emulator 接続への切替も Data レイヤーに閉じた変更で完了します。

## 7. 新しい画面を追加する場合

1. `presentation/pages/<screen_name>/` を作成し、`<screen>_page.dart` と `<screen>_viewmodel.dart` を配置。
2. 必要なら `data/services` や `data/models` に新しいデータ取得ロジックを追加（Firestore の場合は Service で SDK を扱い、Repository でエンティティに変換）。
3. 共通で使う値は `core/constants`・共通スタイルは `core/theme` に寄せる。
4. `presentation/routes.dart` に新しいルートを登録して `TagGameApp` から遷移できるようにする。

## 8. よくある質問

- **Firebase を使う処理はどこに書く？**  
  SDK との直接のやり取りは `data/services/firebase_service.dart` にまとめ、ViewModel からは Repository 経由で呼び出します。

- **API のモックを本物に差し替えるには？**  
  `ApiService` に Dio や `http` を導入して実際のエンドポイントを叩く実装へ差し替えます。UI や ViewModel を触らなくても、Repository 経由で新しいデータが渡るようになります。

---
この構成をベースに、中長期的には `domain/` に UseCase を追加したり、状態管理パッケージ（Riverpod、Bloc など）を導入するとスケールしやすくなります。まずはサンプルを動かしながらレイヤーの責務に慣れていきましょう。
