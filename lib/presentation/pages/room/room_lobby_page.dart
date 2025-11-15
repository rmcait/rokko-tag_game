import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RoomLobbyPageArgs {
  final String roomCode;
  final RoomLobbyMember owner;
  final List<RoomLobbyMember> participants;

  const RoomLobbyPageArgs({
    required this.roomCode,
    required this.owner,
    this.participants = const [],
  });
}

class RoomLobbyMember {
  final String name;
  final String? avatarUrl;

  const RoomLobbyMember({
    required this.name,
    this.avatarUrl,
  });
}

class RoomLobbyPage extends StatelessWidget {
  final RoomLobbyPageArgs args;

  const RoomLobbyPage({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ルームロビー'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'パーティID',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  args.roomCode,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 40,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => _copyRoomCode(context),
                icon: const Icon(Icons.share),
                label: const Text('共有'),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Owner',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _MemberTile(member: args.owner),
                      const SizedBox(height: 24),
                      const Text(
                        '参加メンバー',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (args.participants.isEmpty)
                        const Text(
                          '参加者を待っています…',
                          style: TextStyle(color: Colors.grey),
                        )
                      else
                        ...args.participants
                            .map((member) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _MemberTile(member: member),
                                ))
                            .toList(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.amber.shade200,
                        foregroundColor: Colors.black87,
                      ),
                      onPressed: () => _showPlaceholderAction(context, '役割決め'),
                      child: const Text(
                        '役割決め',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.grey.shade300,
                        foregroundColor: Colors.black54,
                      ),
                      onPressed: () => _showPlaceholderAction(context, 'START'),
                      child: const Text(
                        'START',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _copyRoomCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: args.roomCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('パーティIDをコピーしました')),
    );
  }

  void _showPlaceholderAction(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label はまだ実装されていません')),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final RoomLobbyMember member;

  const _MemberTile({required this.member});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundImage:
              member.avatarUrl != null ? NetworkImage(member.avatarUrl!) : null,
          child: member.avatarUrl == null
              ? const Icon(Icons.person, size: 24)
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            member.name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
