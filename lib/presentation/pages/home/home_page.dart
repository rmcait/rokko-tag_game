import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../routes.dart';
import '../map/map_page.dart';
import 'home_viewmodel.dart';

/// ホーム画面（ログイン後のメイン画面）
class HomePage extends StatelessWidget {
  const HomePage({super.key});

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
      appBar: AppBar(
        title: const Text('鬼ごっこ'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ユーザー情報カード
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        // プロフィール画像
                        CircleAvatar(
                          radius: 30,
                          backgroundImage: user?.photoUrl != null
                              ? NetworkImage(user!.photoUrl!)
                              : null,
                          child: user?.photoUrl == null
                              ? const Icon(Icons.person, size: 30)
                              : null,
                        ),
                        const SizedBox(width: 16),
                        // ユーザー情報
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.displayName ?? 'ゲスト',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                user?.email ?? '匿名ユーザー',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // メニューボタン
                const Text(
                  'メニュー',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // ルーム作成ボタン
                _MenuButton(
                  icon: Icons.add_circle_outline,
                  title: 'ルームを作成',
                  subtitle: '新しいゲームルームを作成する',
                  onTap: () => _startRoomCreation(context),
                ),
                const SizedBox(height: 12),

                // ルーム参加ボタン
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

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
