import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'presentation/routes.dart';
import 'data/services/auth_service.dart';
import 'presentation/pages/login/login_viewmodel.dart';
import 'presentation/pages/home/home_viewmodel.dart';

/// ルーティングとテーマをまとめたアプリのエントリーポイント。
class TagGameApp extends StatelessWidget {
  const TagGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider<LoginViewModel>(
          create: (ctx) => LoginViewModel(ctx.read<AuthService>()),
        ),
        ChangeNotifierProvider<HomeViewModel>(
          create: (ctx) => HomeViewModel(ctx.read<AuthService>()),
        ),
      ],
      child: MaterialApp(
        title: 'Tag Game',
        theme: buildAppTheme(),
        initialRoute: AppRoutes.login,
        onGenerateRoute: AppRouter.onGenerateRoute,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
