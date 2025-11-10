import 'package:flutter/material.dart';
<<<<<<< HEAD
import 'package:provider/provider.dart';
import 'login_viewmodel.dart';

/// ログイン画面
=======

>>>>>>> 9b9f9c963f02aec80ef4b23e24e2d55f611c784e
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
<<<<<<< HEAD
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // アプリロゴ・タイトル
                const Icon(
                  Icons.running_with_errors,
                  size: 100,
                  color: Colors.deepPurple,
                ),
                const SizedBox(height: 24),
                const Text(
                  '鬼ごっこ',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'リアルタイムオンライン鬼ごっこゲーム',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 60),

                // Googleログインボタン
                Consumer<LoginViewModel>(
                  builder: (context, viewModel, child) {
                    if (viewModel.isLoading) {
                      return const CircularProgressIndicator();
                    }

                    return Column(
                      children: [
                        // Googleログインボタン
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final user = await viewModel.signInWithGoogle();
                              if (user != null && context.mounted) {
                                // ログイン成功時はホーム画面へ遷移
                                Navigator.pushReplacementNamed(
                                    context, '/home');
                              }
                            },
                            icon: Image.asset(
                              'assets/google_logo.png',
                              height: 24,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.g_mobiledata, size: 24),
                            ),
                            label: const Text(
                              'Google でログイン',
                              style: TextStyle(fontSize: 16),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black87,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(
                                    color: Colors.grey, width: 1),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 匿名ログインボタン
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final user = await viewModel.signInAnonymously();
                              if (user != null && context.mounted) {
                                // ログイン成功時はホーム画面へ遷移
                                Navigator.pushReplacementNamed(
                                    context, '/home');
                              }
                            },
                            icon: const Icon(Icons.person_outline),
                            label: const Text(
                              'ゲストとしてログイン',
                              style: TextStyle(fontSize: 16),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.deepPurple,
                              side: const BorderSide(
                                  color: Colors.deepPurple, width: 2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),

                        // エラーメッセージ表示
                        if (viewModel.errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    color: Colors.red.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    viewModel.errorMessage!,
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
=======
      appBar: AppBar(title: const Text('ログイン')),
      body: const Center(
        child: Text('ログイン画面の UI をここに実装します。'),
>>>>>>> 9b9f9c963f02aec80ef4b23e24e2d55f611c784e
      ),
    );
  }
}
