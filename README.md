# tag_game
Flutterの環境構築については、こちらのドキュメントにまとめています。
よかったら、見ながら進めてみてー！！


## 1. 開発に必要なもの
- Flutter SDK 3.22 以降（Dart 3.9 系）  
  → `fvm`（Flutter Version Management）で必要なバージョンを自動取得
- Android Studio または VS Code（Flutter プラグイン推奨）
- OS に応じた準備（下記）

### macOS の場合
1. Homebrew が入っていない場合は https://brew.sh/ を参考にインストール
2. `fvm` をインストール
   ```bash
   brew install fvm
   ```
3. Xcode を App Store からインストールし、初回起動でライセンスに同意
4. iOS シミュレーターで使用する「iPhone 17 Pro」に対応した iOS ランタイムを追加
   Xcode を開き、`Settings > Platforms > iOS` から「iOS 18（iPhone 17 Pro が利用可能なバージョン）」をダウンロード

### Windows の場合
1. `fvm` をインストールします。Chocolatey を使う場合:
   ```powershell
   choco install fvm
   ```
   その他の方法は公式ドキュメント https://fvm.app/docs/getting_started/installation を参照
2. Android Studio をインストールし、Android SDK と必要なプラットフォーム（API Level 34 など）をセットアップ
3. Android エミュレーター（Pixel シリーズなど）を作成し、起動できることを確認

Flutter を初めてセットアップした後は、動作確認として次を実行

```bash
flutter doctor
```

これが全てpassすれば準備完了！

## 2. 環境構築手順
1. リポジトリを取得
   ```bash
   git clone <このリポジトリのURL>
   cd tag_game
   ```
2. 初期化コマンドを実行。指定の Flutter SDK を `fvm` で取得し、依存パッケージの取得とエミュレーター起動（OS に応じて iOS または Android）が自動で行なわれる。
   ```bash
   make init
   ```

3. APIkeyの設定を行なってください。（下記はiosの場合）
  ```bash
   cp ios/Runner/Config.example.xcconfig ios/Runner/Config.xcconfig
   ```
  

## 3. アプリを動かす
- 接続済みのデバイスやエミュレーターを確認
  ```bash
  make devices
  ```
- iOS シミュレーターで実行（macOS）
  ```bash
  make run-ios
  ```
- Android エミュレーターで実行
  ```bash
  make run-android
  ```
- リリースビルドをまとめて作成（Android APK と iOS）
  ```bash
  make build
  ```

## 4. テスト
ユニットテストは次のコマンドで実行可能。
```bash
make test
```

## 5. よくあるトラブル
- `flutter doctor` でエラーが出た場合は、表示された指示（Xcode ライセンス承諾、Android SDK の追加など）に従って解消お願いします。
- キャッシュをクリアしたい場合
  ```bash
  make clean
  ```
- 依存関係を再取得したい場合
  ```bash
  make pub-get
  ```
- 自動起動するエミュレーター名が手元と異なるときは、`Makefile` 内の `run-ios` / `run-android` の `-d` で指定しているデバイス ID を自身の環境に合わせて変更お願いします。

## 6. Firebase CLI を使いたい場合（任意）
`firebase_options.dart` や `google-services.json` はリポジトリに含まれているので、CLI を使わなくてもアプリは Firebase に接続できます。Firebase の GUI/CLI でデータを操作したいメンバーだけ、次の準備をしてください。

1. Firebase プロジェクトにアクセス権を持つ Google アカウントで招待されていることを確認。
2. CLI をインストール。
   ```bash
   npm install -g firebase-tools
   dart pub global activate flutterfire_cli
   export PATH="$HOME/.pub-cache/bin:$PATH"   # 必要なら
   ```
3. Firebase にログイン。
   ```bash
   firebase login
   ```
4. これで `firebase apps:list` などの CLI コマンドが使えます。既存設定を変えたくない場合は `flutterfire configure` は実行せず、リポジトリに含まれているファイルをそのまま利用してください。

## 7. 参考リンク
- Flutter 公式ドキュメント: https://docs.flutter.dev/
- Flutter 学習向けチュートリアル: https://docs.flutter.dev/get-started/codelab
