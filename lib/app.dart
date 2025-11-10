import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'presentation/routes.dart';

/// ルーティングとテーマをまとめたアプリのエントリーポイント。
class TagGameApp extends StatelessWidget {
  const TagGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tag Game',
      theme: buildAppTheme(),
      initialRoute: AppRoutes.login,
      onGenerateRoute: AppRouter.onGenerateRoute,
      debugShowCheckedModeBanner: false,
    );
  }
}
