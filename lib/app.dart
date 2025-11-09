import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'data/services/auth_service.dart';
import 'presentation/pages/login/login_page.dart';
import 'presentation/pages/login/login_viewmodel.dart';
import 'presentation/pages/home/home_page.dart';
import 'presentation/pages/home/home_viewmodel.dart';

/// アプリケーションのルートウィジェット
class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    // Firebase未初期化の場合はシンプルな構成
    if (!firebaseReady) {
      return MaterialApp(
        title: '鬼ごっこ',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning, size: 64, color: Colors.orange),
                SizedBox(height: 16),
                Text(
                  'Firebase が初期化されていません',
                  style: TextStyle(fontSize: 18),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // AuthServiceをアプリ全体で提供
    return MultiProvider(
      providers: [
        // AuthServiceのシングルトン提供
        Provider<AuthService>(
          create: (_) => AuthService(),
        ),
        // LoginViewModelの提供
        ChangeNotifierProvider<LoginViewModel>(
          create: (context) => LoginViewModel(
            context.read<AuthService>(),
          ),
        ),
        // HomeViewModelの提供
        ChangeNotifierProvider<HomeViewModel>(
          create: (context) => HomeViewModel(
            context.read<AuthService>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: '鬼ごっこ',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        // 認証状態に応じて初期画面を切り替え
        home: Consumer<AuthService>(
          builder: (context, authService, _) {
            return StreamBuilder(
              stream: authService.authStateChanges,
              builder: (context, snapshot) {
                // エラーが発生した場合
                if (snapshot.hasError) {
                  return Scaffold(
                    body: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error, size: 64, color: Colors.red),
                          const SizedBox(height: 16),
                          Text(
                            'エラーが発生しました',
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            snapshot.error.toString(),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // 認証状態を確認中
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                // ログイン済みの場合はホーム画面へ
                if (snapshot.hasData) {
                  return const HomePage();
                }

                // 未ログインの場合はログイン画面へ
                return const LoginPage();
              },
            );
          },
        ),
        routes: {
          '/login': (context) => const LoginPage(),
          '/home': (context) => const HomePage(),
        },
      ),
    );
  }
}
