import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'login_viewmodel.dart';

/// ログイン画面（タイトル画面）
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  static const _accentColor = Color(0xFF6A4CD3); // お好みで変更OK

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // --------------------------
                // ① ロゴ＋タイトル
                // --------------------------
                Padding(
                  padding:
                      const EdgeInsets.only(top: 40, left: 24, right: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ★ここをあなたのロゴSVGに差し替え
                      SvgPicture.asset(
                        'assets/svg/app_logo.svg',
                        // 例: SparkTagのロゴsvg
                        height: size.height * 0.16,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '鬼ごっこ',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: _accentColor,
                          letterSpacing: 2,
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
                    ],
                  ),
                ),

                // --------------------------
                // ② ログインボタン群
                // --------------------------
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Consumer<LoginViewModel>(
                    builder: (context, viewModel, child) {
                      if (viewModel.isLoading) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: CircularProgressIndicator(),
                        );
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Google ログイン
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final user =
                                    await viewModel.signInWithGoogle();
                                if (user != null && context.mounted) {
                                  Navigator.pushReplacementNamed(
                                      context, '/home');
                                }
                              },
                              icon: Image.asset(
                                'assets/google_logo.png',
                                height: 22,
                                errorBuilder:
                                    (context, error, stackTrace) =>
                                        const Icon(Icons.g_mobiledata,
                                            size: 22),
                              ),
                              label: const Text(
                                'Google でログイン',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black87,
                                elevation: 3,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  side: const BorderSide(
                                    color: Color(0xFFE0E0E0),
                                    width: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ゲストログイン
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final user =
                                    await viewModel.signInAnonymously();
                                if (user != null && context.mounted) {
                                  Navigator.pushReplacementNamed(
                                      context, '/home');
                                }
                              },
                              icon: const Icon(Icons.person_outline),
                              label: const Text(
                                'ゲストとしてログイン',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _accentColor,
                                side: const BorderSide(
                                  color: _accentColor,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                            ),
                          ),

                          // エラー表示
                          if (viewModel.errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.red.shade200,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.red.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      viewModel.errorMessage!,
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                        fontSize: 13,
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
                ),

                // --------------------------
                // ③ 下部キャラクターイラスト
                // --------------------------
                // 画像が画面下に張り付くようにする
                SizedBox(
                  height: size.height * 0.32,
                  width: double.infinity,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: SvgPicture.asset(
                      // ★ここを走るキャラのSVGに差し替え
                      'assets/svg/runner_hero.svg',
                      fit: BoxFit.cover,
                      width: size.width,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}