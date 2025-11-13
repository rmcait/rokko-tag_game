# OS判定
OS := $(shell uname)


# 初期化：Flutter SDKインストール & 依存関係の取得
init:
	fvm install
	fvm flutter pub get

ifeq ($(OS), Darwin)
	@echo "macOSが検出されました。iOSシミュレータを起動します。"
	@echo "シミュレータ起動を待っています..."
	make run-ios
else
	@echo "Windows/Linux環境が検出されました。Androidエミュレータを起動します。"
	@echo "シミュレータ起動を待っています..."
	make run-android
endif

# 依存関係の再取得
pub-get:
	fvm flutter pub get

# クリーンビルド
clean:
	fvm flutter clean
	fvm flutter pub get

# 実機/エミュレータ
devices:
	fvm flutter devices

# iOSエミュレータ
run-ios:
	fvm flutter emulators --launch apple_ios_simulator
	sleep 7
	fvm flutter run -d "iPhone 17 Pro"

# Androidエミュレータ
run-android:
	fvm flutter emulators --launch Pixel_8
	sleep 7
	fvm flutter run -d "emulator-5554"

# 両OS共通のbuildコマンド
build:
	fvm flutter build apk
	fvm flutter build ios

# テスト実行
test:
	fvm flutter test