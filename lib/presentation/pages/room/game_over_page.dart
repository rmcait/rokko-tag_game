import 'package:flutter/material.dart';
import '../../../data/services/party_service.dart';
import '../../routes.dart';

class GameOverPageArgs {
  final PartyLobbyData lobby;
  final String currentUserId;
  final String gameId;

  const GameOverPageArgs({
    required this.lobby,
    required this.currentUserId,
    required this.gameId,
  });
}

class GameOverPage extends StatelessWidget {
  final GameOverPageArgs args;

  const GameOverPage({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GAME OVER')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sentiment_dissatisfied, size: 80, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              '捕まってしまいました…！',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                // ロビーに戻る
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
    );
  }
}