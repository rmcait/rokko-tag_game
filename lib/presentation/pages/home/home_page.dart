import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../routes.dart';
import '../map/map_page.dart';
import 'home_viewmodel.dart';

/// ホーム画面（ログイン後のメイン画面）
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // ログイン画面と世界観を合わせるカラー
  static const _accentPurple = Color(0xFF6A4CD3);
  static const _softYellow = Color(0xFFFFF7DA);      // AppBar やアイコン背景
  static const _cardBg = Color(0xFFFFFDF5);          // カードの背景

  Future<void> _startRoomCreation(BuildContext context) async {
    final viewModel = context.read<HomeViewModel>();
    final user = viewModel.currentUser;
    if (user == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ユーザー情報を取得できませんでした')),
        );
      }
      return;
    }

    await Navigator.pushNamed(
      context,
      AppRoutes.map,
      arguments: MapPageArgs(
        roomCreation: RoomCreationParams(owner: user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _softYellow,
        foregroundColor: Colors.black87,
        centerTitle: true,
        title: const Text(
          '鬼ごっこ',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        actions: [
          // ログアウトボタン
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final viewModel = context.read<HomeViewModel>();
              await viewModel.signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
            tooltip: 'ログアウト',
          ),
        ],
      ),
      body: Consumer<HomeViewModel>(
        builder: (context, viewModel, child) {
          final user = viewModel.currentUser;

          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ───── ユーザー情報カード ─────
                _ProfileCard(
                  displayName: user?.displayName ?? 'ゲスト',
                  email: user?.email ?? '匿名ユーザー',
                  photoUrl: user?.photoUrl,
                ),
                const SizedBox(height: 32),

                // ───── メニュー見出し ─────
                const Text(
                  'メニュー',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 64,
                  height: 3,
                  decoration: BoxDecoration(
                    color: _accentPurple.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 20),

                // ───── メニューボタン ─────
                _MenuButton(
                  icon: Icons.add_circle_outline,
                  title: 'ルームを作成',
                  subtitle: '新しいゲームルームを作成する',
                  onTap: () => _startRoomCreation(context),
                ),
                const SizedBox(height: 12),
                _MenuButton(
                  icon: Icons.group_add,
                  title: 'ルームに参加',
                  subtitle: '既存のゲームルームに参加する',
                  onTap: () {
                    Navigator.pushNamed(context, AppRoutes.joinRoom);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// ユーザー情報カード（プロフィールを少し正方形寄り＋装飾）
class _ProfileCard extends StatelessWidget {
  final String displayName;
  final String email;
  final String? photoUrl;

  const _ProfileCard({
    required this.displayName,
    required this.email,
    this.photoUrl,
  });

  static const _accentPurple = Color(0xFF6A4CD3);
  static const _softYellow = Color(0xFFFFF7DA);
  static const _cardBg = Color(0xFFFFFDF5);

  @override
  Widget build(BuildContext context) {
    final initial = displayName.isNotEmpty ? displayName.characters.first : 'ゲ';

    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // 正方形寄りのアイコン枠
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: _softYellow,
              borderRadius: BorderRadius.circular(18),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: photoUrl != null
                  ? Image.network(
                      photoUrl!,
                      fit: BoxFit.cover,
                    )
                  : Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: _accentPurple,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          // ユーザー情報＋タグ
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accentPurple.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: Colors.green,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'オンライン',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _accentPurple,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// メニューボタンウィジェット
class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  static const _accentPurple = Color(0xFF6A4CD3);
  static const _softYellow = Color(0xFFFFF7DA);
  static const _cardBg = Color(0xFFFFFDF5);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _cardBg,
      elevation: 2,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // 左のアイコンバッジ（黄色＋紫）
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _softYellow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: _accentPurple,
                ),
              ),
              const SizedBox(width: 16),
              // テキスト
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: Colors.black45,
              ),
            ],
          ),
        ),
      ),
    );
  }
}