import 'package:flutter/material.dart';

/// ルーティング設定
class AppRoutes {
  static const String login = '/login';
  static const String home = '/home';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case login:
        return MaterialPageRoute(
          builder: (_) => const Placeholder(), // LoginPageで置き換え
        );
      case home:
        return MaterialPageRoute(
          builder: (_) => const Placeholder(), // HomePageで置き換え
        );
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('ルートが見つかりません: ${settings.name}'),
            ),
          ),
        );
    }
  }
}
