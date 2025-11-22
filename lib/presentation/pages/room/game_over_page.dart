import 'package:flutter/material.dart';
import '../../../data/services/party_service.dart';
import '../../routes.dart';

class GameOverPageArgs {
  final PartyLobbyData lobby;
  final String currentUserId;
  final String gameId;

  /// 鬼チームが勝ったかどうか
  final bool taggersWin;

  /// 「自分のいるチーム」が勝ったかどうか
  final bool isMyTeamWin;

  /// 捕まった人数（RUNNER）
  final int capturedCount;

  /// RUNNER の総数
  final int totalRunners;

  const GameOverPageArgs({
    required this.lobby,
    required this.currentUserId,
    required this.gameId,
    required this.taggersWin,
    required this.isMyTeamWin,
    required this.capturedCount,
    required this.totalRunners,
  });
}

class GameOverPage extends StatelessWidget {
  final GameOverPageArgs args;

  const GameOverPage({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    final bigText = args.taggersWin ? '鬼チームの勝ち！' : '逃走チームの勝ち！';
    final subText = args.isMyTeamWin
        ? 'あなたのチームの勝利です！'
        : 'あなたのチームは負けてしまいました…';

    final iconData =
        args.isMyTeamWin ? Icons.emoji_events : Icons.sentiment_dissatisfied;
    final iconColor =
        args.isMyTeamWin ? Colors.amber : Colors.redAccent;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RESULT'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconData, size: 80, color: iconColor),
              const SizedBox(height: 16),
              Text(
                bigText,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subText,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 0,
                color: Colors.grey.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '確保された逃走者',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${args.capturedCount} / ${args.totalRunners}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    AppRoutes.home,
                    (route) => false,
                  );
                },
                child: const Text('ホームへ戻る'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}