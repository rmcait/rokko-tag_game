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
| `data/services/api_service.dart` | REST API など外部サービスへの I/O を担当（サンプルではモック）。 |
| `data/services/firebase_service.dart` | FirebaseAuth など Firebase SDK との境界。 |
| `data/models/sample_model.dart` | API レスポンスをアプリ内部の `SampleEntity` に変換。 |
| `data/repository.dart` | ViewModel から呼び出す窓口。Service からモデルを受け取り Entity を返す。 |

## 4. Domain レイヤー

- `domain/entities.dart` には `SampleEntity` を定義。  
  UI・データ取得どちらのパッケージにも依存しない「純粋なデータ構造」です。

## 5. Presentation レイヤー

- `presentation/pages/home` … Home 画面と `HomeViewModel`。`SampleRepository` からメッセージを取得し、`notifyListeners()` で UI を更新します。
- `presentation/pages/login` … ログイン画面の雛形。UI を作りたい場合はここから。
- `presentation/widgets/custom_button.dart` … アプリ共通のボタン。
- `presentation/routes.dart` … 画面パスを一元管理。`AppRoutes.home` など定数で指定。

### ViewModel とデータフロー

1. `HomePage` が `HomeViewModel.load()` を呼び出す。
2. `HomeViewModel` が `SampleRepository` に依頼してデータを取得。
3. `SampleRepository` → `ApiService` → `SampleModel` と処理が進み、最終的に `SampleEntity` が UI に渡る。
4. ViewModel が `notifyListeners()` を呼び、`HomePage` が再描画される。

## 6. 新しい画面を追加する場合

1. `presentation/pages/<screen_name>/` を作成し、`<screen>_page.dart` と `<screen>_viewmodel.dart` を配置。
2. 必要なら `data/services` や `data/models` に新しいデータ取得ロジックを追加。(firebaseからfirestoreへの接続)
3. 共通で使う値は `core/constants`・共通スタイルは `core/theme` に寄せる。
4. `presentation/routes.dart` に新しいルートを登録して `TagGameApp` から遷移できるようにする。

## 7. よくある質問

- **Firebase を使う処理はどこに書く？**  
  SDK との直接のやり取りは `data/services/firebase_service.dart` にまとめ、ViewModel からは Repository 経由で呼び出します。

- **API のモックを本物に差し替えるには？**  
  `ApiService` に Dio や `http` を導入して実際のエンドポイントを叩く実装へ差し替えます。UI や ViewModel を触らなくても、Repository 経由で新しいデータが渡るようになります。

---
この構成をベースに、中長期的には `domain/` に UseCase を追加したり、状態管理パッケージ（Riverpod、Bloc など）を導入するとスケールしやすくなります。まずはサンプルを動かしながらレイヤーの責務に慣れていきましょう。
