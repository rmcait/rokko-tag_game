import 'package:flutter/foundation.dart';

/// シンプルなロガー。必要に応じて Firebase Crashlytics 等に差し替え可能。
class AppLogger {
  const AppLogger._();

  static void info(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[INFO] $message');
    }
  }
}
