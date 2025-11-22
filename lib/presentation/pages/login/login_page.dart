import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import 'login_viewmodel.dart';

/// ログイン画面（タイトル画面）
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  // カラー設定（SparkTag の世界観に合わせて）
  static const _accentColor = Color(0xFF6A4CD3); // メインのパープル
  static const _bgTop = Color(0xFFFFF7DA);       // 上側：薄い黄色
  static const _bgBottom = Color(0xFFFFFFFF);    // 下側：白

  late final AnimationController _starController;

  @override
  void initState() {
    super.initState();
    // 星をふわふわ動かすアニメーション
    _starController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _starController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            // ① 背景グラデーション
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_bgTop, _bgBottom],
                  ),
                ),
              ),
            ),

            // ② 星のアニメーションレイヤー
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _starController,
                builder: (context, _) {
                  return Stack(
                    children: _buildStars(size, _starController),
                  );
                },
              ),
            ),
          ),

            // ③ メインコンテンツ
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ───── ロゴ＆タグライン ─────
                      Padding(
                        padding: const EdgeInsets.only(
                            top: 56, left: 24, right: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // アプリロゴ（SparkTag）
                            SvgPicture.asset(
                              'assets/svg/app_logo.svg',
                              height: size.height * 0.22,
                            ),
                            const SizedBox(height: 24),
                            // タイトルテキストは削除して、タグラインだけにする
                            const Text(
                              'リアルタイムオンライン鬼ごっこゲーム',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.black54,
                                height: 1.6,
                                letterSpacing: 1.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),

                      // ───── ログインボタン群 ─────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
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
                                // Google ログイン（白カード風）
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      final user = await viewModel
                                          .signInWithGoogle();
                                      if (user != null && context.mounted) {
                                        Navigator.pushReplacementNamed(
                                            context, '/home');
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.g_mobiledata,
                                      size: 24,
                                    ),
                                    label: const Text(
                                      'Google でログイン',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black87,
                                      elevation: 4,
                                      shadowColor:
                                          Colors.black.withOpacity(0.10),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        side: BorderSide(
                                          color:
                                              _accentColor.withOpacity(0.18),
                                          width: 1.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),

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

                      // ───── 下部キャラクターイラスト ─────
                      SizedBox(
                        height: size.height * 0.36,
                        width: double.infinity,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: SvgPicture.asset(
                            'assets/svg/2.svg', // 走っているキャラ
                            width: size.width * 0.95,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 星をまとめて生成する
List<Widget> _buildStars(Size size, Animation<double> animation) {
  final t = animation.value;

  // 星の初期位置データ（x, y, size, opacity）
  final stars = [
    [0.15, 0.12, 18.0, 0.8],
    [0.35, 0.18, 14.0, 0.7],
    [0.55, 0.10, 20.0, 0.6],
    [0.75, 0.15, 16.0, 0.75],
    [0.20, 0.26, 22.0, 0.8],
    [0.65, 0.28, 18.0, 0.7],
    [0.85, 0.22, 14.0, 0.6],
    [0.10, 0.32, 20.0, 0.5],
    [0.45, 0.30, 16.0, 0.65],
    [0.80, 0.12, 22.0, 0.75],
  ];

  double float(double base, double range) =>
      base + (t - 0.5) * 2 * range; // -range〜range の揺れ

  return stars.map((data) {
    final x = data[0] as double;
    final y = data[1] as double;
    final sizePx = data[2] as double;
    final opacity = data[3] as double;

    return Positioned(
      left: size.width * x,
      top: float(size.height * y, 8),
      child: Opacity(
        opacity: opacity,
        child: Icon(
          Icons.star_rounded,
          size: sizePx,
          color: const Color(0xFFFFD54F),
        ),
      ),
    );
  }).toList();
}
}