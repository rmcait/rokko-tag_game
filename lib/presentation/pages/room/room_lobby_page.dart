import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../data/services/party_service.dart';
import 'package:tag_game/presentation/pages/map/map_page.dart';
import 'package:tag_game/presentation/pages/map/game_map_page.dart';
import 'room_game_page.dart';

class RoomLobbyPageArgs {
  final PartyLobbyData lobby;
  final String currentUserId;
  final bool allowFieldReselect;
  final bool deletePartyOnExit;
  final bool promptDurationSelection;

  const RoomLobbyPageArgs({
    required this.lobby,
    required this.currentUserId,
    this.allowFieldReselect = false,
    this.deletePartyOnExit = false,
    this.promptDurationSelection = false,
  });
}

class RoomLobbyPage extends StatefulWidget {
  final RoomLobbyPageArgs args;

  const RoomLobbyPage({super.key, required this.args});

  @override
  State<RoomLobbyPage> createState() => _RoomLobbyPageState();
}

class _RoomLobbyPageState extends State<RoomLobbyPage> {
  final PartyService _partyService = PartyService();
  bool _isAssigning = false;
  bool _isStartingGame = false;
  PartyLobbyData? _latestLobby;
  bool _durationPromptScheduled = false;

  bool _navigatedToGame = false;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('役割決め'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final lobby = _latestLobby;
              if (lobby != null && _shouldReturnToFieldSelection(lobby)) {
                await _exitToFieldSelection(lobby);
              } else {
                Navigator.of(context).maybePop();
              }
            },
          ),
        ),
        body: SafeArea(
          child: StreamBuilder<PartyLobbyData?>(
            stream: _partyService.watchPartyLobby(widget.args.lobby.partyId),
            initialData: widget.args.lobby,
            builder: (context, snapshot) {
              final lobby = snapshot.data ?? _latestLobby ?? widget.args.lobby;
              if (lobby == null) {
                return const Center(
                  child: Text('ルーム情報を取得できませんでした'),
                );
              }
              _latestLobby = lobby;
              _maybeShowDurationPrompt(lobby);
              _maybeNavigateToGame(lobby);
              final members = lobby.allMembers;
              final currentMember =
                  _findMemberById(members, widget.args.currentUserId);
              return Padding(
                padding: const EdgeInsets.all(24),
                child: _LobbyLayout(
                  lobby: lobby,
                  members: members,
                  currentMember: currentMember,
                  isOwner: lobby.owner.userId == widget.args.currentUserId,
                  isAssigning: _isAssigning,
                  rolesAssigned: members.isNotEmpty &&
                      members.every(
                        (m) => m.role != PartyMemberRole.pending,
                      ),
                  onAssignRoles: currentMember == null
                      ? null
                      : () => _handleAssignRoles(lobby, currentMember),
                  onViewRoles: currentMember == null
                      ? null
                      : () => _openRoleReveal(lobby, currentMember),
                  onCopyCode: () => _copyRoomCode(lobby.inviteCode),
                  isStartingGame: _isStartingGame,
                  onStartGame: lobby.owner.userId == widget.args.currentUserId
                      ? () => _startGame(lobby)
                      : null,
                  onEditDuration: (lobby.owner.userId == widget.args.currentUserId &&
                          members.every((m) => m.role == PartyMemberRole.pending))
                      ? () => _showDurationPicker(lobby)
                      : null,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<bool> _handleWillPop() async {
    final lobby = _latestLobby;
    if (lobby != null && _shouldReturnToFieldSelection(lobby)) {
      await _exitToFieldSelection(lobby);
      return false;
    }
    return true;
  }

  bool _shouldReturnToFieldSelection(PartyLobbyData lobby) {
    return widget.args.allowFieldReselect &&
        lobby.owner.userId == widget.args.currentUserId;
  }

  void _maybeShowDurationPrompt(PartyLobbyData lobby) {
    if (_durationPromptScheduled) return;
    if (!widget.args.promptDurationSelection) return;
    if (lobby.owner.userId != widget.args.currentUserId) return;
    final rolesAssigned =
        lobby.allMembers.every((m) => m.role != PartyMemberRole.pending);
    if (rolesAssigned) return;
    _durationPromptScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _showDurationPicker(lobby);
    });
  }

  Future<void> _showDurationPicker(PartyLobbyData lobby) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _DurationPickerSheet(
        initialValue: lobby.durationMinutes,
      ),
    );
    if (selected != null) {
      await _partyService.updatePartyDuration(lobby.partyId, selected);
      final refreshed =
          await _partyService.fetchPartyLobbyById(lobby.partyId) ??
              lobby.copyWith(durationMinutes: selected);
      if (mounted) {
        setState(() {
          _latestLobby = refreshed;
        });
      }
    }
  }

  PartyMemberData? _findMemberById(
    List<PartyMemberData> members,
    String userId,
  ) {
    for (final member in members) {
      if (member.userId == userId) {
        return member;
      }
    }
    return null;
  }

  Future<void> _handleAssignRoles(
    PartyLobbyData lobby,
    PartyMemberData currentMember,
  ) async {
    if (_isAssigning) return;
    setState(() => _isAssigning = true);
    try {
      await _partyService.assignRolesRandomly(lobby.partyId);
      final updated =
          await _partyService.fetchPartyLobbyById(lobby.partyId) ?? lobby;
      if (!mounted) return;
      final refreshedMember = updated.allMembers.firstWhere(
        (m) => m.userId == currentMember.userId,
        orElse: () => currentMember,
      );
      await _openRoleReveal(updated, refreshedMember);
    } on PartyJoinException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('役割決めに失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isAssigning = false);
      }
    }
  }

  Future<void> _openRoleReveal(
    PartyLobbyData lobby,
    PartyMemberData currentMember,
  ) async {
    final data = lobby;
    final me = currentMember;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoleRevealSheet(
          lobby: data,
          currentMember: me,
        ),
      ),
    );
  }

  Future<void> _startGame(PartyLobbyData lobby) async {
  if (_isStartingGame) return;
  setState(() => _isStartingGame = true);

  try {
    // 1. gameId を決める（partyId ベースでOK）
    final gameId = 'game_${lobby.partyId}';

    final firestore = FirebaseFirestore.instance;
    final gameDoc = firestore.collection('gameSessions').doc(gameId);
    final partyDoc = firestore.collection('parties').doc(lobby.partyId);

    final batch = firestore.batch();

    // 2. gameSessions/{gameId} を作成
    batch.set(gameDoc, {
      'partyId': lobby.partyId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 3. gameSessions/{gameId}/players に全メンバーを書き込む
    final playersRef = gameDoc.collection('players');
    for (final m in lobby.allMembers) {
      final ref = playersRef.doc(m.userId);
      batch.set(
        ref,
        {
          'userId': m.userId,
          'displayName': m.name,
          'role': m.role.code, // TAGGER / RUNNER / PENDING
          'caught': false,
          'inside': false,
          'lastLocation': null,
        },
        SetOptions(merge: true),
      );
    }

    // 4. parties/{partyId} 側にも状態を保存
    batch.update(partyDoc, {
      'status': 'PLAYING',
      'activeGameId': gameId,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // まとめて反映
    await batch.commit();

    // 5. 自分のプレイヤーIDを拾ってゲーム画面へ
    final me = _findMemberById(lobby.allMembers, widget.args.currentUserId);
    if (!mounted || me == null) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameMapPage(
          gameId: gameId,
          playerId: me.userId,
        ),
      ),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('ゲーム開始に失敗しました: $e')),
    );
  } finally {
    if (mounted) {
      setState(() => _isStartingGame = false);
    }
  }
}

    await batch.commit();
    // ★ 3. parties/{partyId} にゲーム開始フラグ＆gameId を保存
    await FirebaseFirestore.instance
        .collection('parties')
        .doc(lobby.partyId)
        .update({
      'status': 'PLAYING',      // もともと "WAITING" になってたやつ
      'activeGameId': gameId,   // 新しく追加するフィールド
    });

    // ★ 4. ホスト自身もすぐゲーム画面へ
    final me = _findMemberById(lobby.allMembers, widget.args.currentUserId);
    if (!mounted || me == null) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameMapPage(
          gameId: gameId,
          playerId: me.userId,
        ),
      ),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('ゲーム開始に失敗しました: $e')),
    );
  } finally {
    if (mounted) {
      setState(() => _isStartingGame = false);
    }
  }
}
void _maybeNavigateToGame(PartyLobbyData lobby) {
  // すでに遷移していたら何もしない
  debugPrint(
    '[RoomLobby] maybeNavigateToGame '
    'status=${lobby.status}, activeGameId=${lobby.activeGameId}, '
    'navigated=$_navigatedToGame, currentUser=${widget.args.currentUserId}',
  );
  if (_navigatedToGame) return;

  // Firestore 上の status が PLAYING でなければまだ待機
  if (lobby.status != 'PLAYING') return;

  // activeGameId が入っていないとダメ
  final gameId = lobby.activeGameId;
  if (gameId == null || gameId.isEmpty) return;

  // 自分の PartyMember を探す
  final me = _findMemberById(lobby.allMembers, widget.args.currentUserId);
  if (me == null) return;

  _navigatedToGame = true;

  // ビルド中なのでフレーム終了後にナビゲーション
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameMapPage(
          gameId: gameId,
          playerId: me.userId,
        ),
      ),
    );
  });
}
  void _copyRoomCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('パーティIDをコピーしました')),
    );
  }

  Future<void> _exitToFieldSelection(PartyLobbyData lobby) async {
    if (widget.args.deletePartyOnExit &&
        lobby.owner.userId == widget.args.currentUserId) {
      await _partyService.deleteParty(lobby.partyId);
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      RoomLobbyExitResult(
        partyDeleted: widget.args.deletePartyOnExit &&
            lobby.owner.userId == widget.args.currentUserId,
      ),
    );
  }
}

class _LobbyLayout extends StatelessWidget {
  final PartyLobbyData lobby;
  final List<PartyMemberData> members;
  final PartyMemberData? currentMember;
  final bool isOwner;
  final bool isAssigning;
  final VoidCallback? onAssignRoles;
  final VoidCallback onCopyCode;
  final bool rolesAssigned;
  final VoidCallback? onViewRoles;
  final bool isStartingGame;
  final VoidCallback? onStartGame;
  final VoidCallback? onEditDuration;

  const _LobbyLayout({
    required this.lobby,
    required this.members,
    required this.currentMember,
    required this.isOwner,
    required this.isAssigning,
    required this.onAssignRoles,
    required this.onCopyCode,
    required this.rolesAssigned,
    required this.onViewRoles,
    required this.isStartingGame,
    required this.onStartGame,
    this.onEditDuration,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedMember =
        currentMember ?? (members.isNotEmpty ? members.first : null);
    final ownerMember = lobby.owner;
    final participantTiles = lobby.participants
        .map(
          (member) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _LobbyMemberTile(
                  member: member,
                  isCurrentUser: member.userId == currentMember?.userId,
                  isOwner: false,
                  showRole: rolesAssigned,
                ),
              ),
        )
        .toList();

    Widget memberSection() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Owner',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _LobbyMemberTile(
            member: ownerMember,
            isCurrentUser: ownerMember.userId == currentMember?.userId,
            isOwner: true,
            showRole: rolesAssigned,
          ),
          const SizedBox(height: 24),
          const Text(
            '参加メンバー',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (participantTiles.isEmpty)
            const _EmptyMembersMessage()
          else
            ...participantTiles,
        ],
      );
    }

    Widget roleButton() {
      final isReveal = rolesAssigned;
      final bool isEnabled = isReveal
          ? onViewRoles != null
          : (isOwner && onAssignRoles != null && !isAssigning);
      final Widget label = isReveal
          ? const Text('役割を見る')
          : isAssigning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isOwner ? '役割決め' : 'ホストが操作します');

      final Color activeColor = const Color(0xFFFFE082);
      final Color disabledColor = theme.colorScheme.surfaceVariant;

      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: isEnabled ? activeColor : disabledColor,
            foregroundColor: Colors.black87,
            disabledForegroundColor: Colors.black45,
          ),
          onPressed: isEnabled
              ? (isReveal ? onViewRoles : onAssignRoles)
              : null,
          child: label,
        ),
      );
    }

    Widget startButton() {
      final canStart =
          rolesAssigned && onStartGame != null && !isStartingGame;
      final Color activeColor = const Color(0xFFFFE082);
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: canStart ? activeColor : Colors.grey.shade300,
            foregroundColor: Colors.black87,
          ),
          onPressed: canStart ? onStartGame : null,
          child: isStartingGame
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('START'),
        ),
      );
    }

    final buttons = Column(
      children: [
        if (resolvedMember != null) ...[
          _RoleHeroPanel(
            role: resolvedMember.role,
          ),
          const SizedBox(height: 24),
        ],
        roleButton(),
        const SizedBox(height: 12),
        startButton(),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final header = _RoomCodeHeader(
          code: lobby.inviteCode,
          onCopy: onCopyCode,
          durationMinutes: lobby.durationMinutes,
          onEditDuration: onEditDuration,
        );

        if (constraints.maxHeight < 620) {
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 24),
                memberSection(),
                const SizedBox(height: 24),
                buttons,
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: memberSection(),
              ),
            ),
            const SizedBox(height: 24),
            buttons,
          ],
        );
      },
    );
  }
}

class _RoomCodeHeader extends StatelessWidget {
  final String code;
  final VoidCallback onCopy;
  final int durationMinutes;
  final VoidCallback? onEditDuration;

  const _RoomCodeHeader({
    required this.code,
    required this.onCopy,
    required this.durationMinutes,
    this.onEditDuration,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'パーティID',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            code,
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall?.copyWith(
              letterSpacing: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: onCopy,
          child: const Text('共有'),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'ゲーム時間: ${durationMinutes}分',
              style: theme.textTheme.bodyMedium,
            ),
            if (onEditDuration != null) ...[
              const SizedBox(width: 12),
              TextButton(
                onPressed: onEditDuration,
                child: const Text('変更'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _LobbyMemberTile extends StatelessWidget {
  final PartyMemberData member;
  final bool isCurrentUser;
  final bool isOwner;
  final bool showRole;

  const _LobbyMemberTile({
    required this.member,
    required this.isCurrentUser,
    required this.isOwner,
    this.showRole = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundImage:
              member.avatarUrl != null ? NetworkImage(member.avatarUrl!) : null,
          child: member.avatarUrl == null
              ? Text(member.name.isNotEmpty ? member.name[0] : '?')
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isCurrentUser ? '${member.name}（あなた）' : member.name,
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
              if (showRole)
                Text(
                  member.role == PartyMemberRole.tagger ? 'おに' : '逃走',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
        if (isOwner)
          Icon(
            Icons.emoji_events,
            size: 18,
            color: Colors.amber.shade600,
          ),
        if (showRole) ...[
          const SizedBox(width: 8),
          _RoleChip(role: member.role),
        ],
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  final PartyMemberRole role;

  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final palette = _RolePresentation.of(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: palette.accent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        palette.chipLabel,
        style: TextStyle(
          color: palette.accent,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _RoleHeroPanel extends StatelessWidget {
  final PartyMemberRole role;

  const _RoleHeroPanel({
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _RolePresentation.of(role);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'あなたの役割',
            style: theme.textTheme.titleMedium?.copyWith(
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            palette.heroTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: palette.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            palette.heroSubtitle,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _EmptyMembersMessage extends StatelessWidget {
  const _EmptyMembersMessage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '参加者を待っています…',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _RolePresentation {
  final Color accent;
  final Color background;
  final String heroTitle;
  final String heroSubtitle;
  final String chipLabel;
  final IconData icon;

  const _RolePresentation({
    required this.accent,
    required this.background,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.chipLabel,
    required this.icon,
  });

  static _RolePresentation of(PartyMemberRole role) {
    switch (role) {
      case PartyMemberRole.tagger:
        return _RolePresentation(
          accent: const Color(0xFFE57373),
          background: const Color(0xFFFFEBEE),
          heroTitle: 'おに側',
          heroSubtitle: '全員を捕まえて勝利を目指そう',
          chipLabel: 'おに',
          icon: Icons.local_fire_department,
        );
      case PartyMemberRole.runner:
        return _RolePresentation(
          accent: const Color(0xFF42A5F5),
          background: const Color(0xFFE3F2FD),
          heroTitle: '逃走側',
          heroSubtitle: '仲間と協力して最後まで逃げ切ろう',
          chipLabel: '逃走',
          icon: Icons.directions_run,
        );
      case PartyMemberRole.pending:
      default:
        return _RolePresentation(
          accent: Colors.grey,
          background: Colors.grey.shade200,
          heroTitle: '役割未決定',
          heroSubtitle: 'ホストが「役割決め」を押すと結果が表示されます',
          chipLabel: '待機中',
          icon: Icons.hourglass_bottom,
        );
    }
  }
}

class RoleRevealSheet extends StatelessWidget {
  final PartyLobbyData lobby;
  final PartyMemberData currentMember;

  const RoleRevealSheet({
    super.key,
    required this.lobby,
    required this.currentMember,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _RolePresentation.of(currentMember.role);
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: palette.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '役割結果',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: palette.accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('タップで戻る'),
                  ],
                ),
                const SizedBox(height: 16),
                _RoleHeroPanel(role: currentMember.role),
                const SizedBox(height: 24),
                Expanded(
                  child: Card(
                    elevation: 0,
                    color: Colors.white.withOpacity(0.85),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ListView.separated(
                        itemCount: lobby.allMembers.length,
                        itemBuilder: (context, index) {
                          final member = lobby.allMembers[index];
                          final palette = _RolePresentation.of(member.role);
                          final isCurrent =
                              member.userId == currentMember.userId;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundImage: member.avatarUrl != null
                                  ? NetworkImage(member.avatarUrl!)
                                  : null,
                            ),
                            title: Text(
                              isCurrent
                                  ? '${member.name}（あなた）'
                                  : member.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: _RoleChip(role: member.role),
                            subtitle: Text(
                              palette.heroTitle,
                              style: TextStyle(color: palette.accent),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) =>
                            const Divider(height: 24),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '画面をタップするとロビーに戻ります。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DurationPickerSheet extends StatelessWidget {
  final int initialValue;

  const _DurationPickerSheet({required this.initialValue});

  @override
  Widget build(BuildContext context) {
    final options = <int>[5, 10, 15];
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        builder: (context, controller) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                'ゲーム時間を選択',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final minutes = options[index];
                    return ListTile(
                      title: Text('$minutes 分'),
                      trailing: initialValue == minutes
                          ? const Icon(Icons.check, color: Colors.green)
                          : null,
                      onTap: () => Navigator.of(context).pop(minutes),
                    );
                  },
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('キャンセル'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoomLobbyExitResult {
  final bool partyDeleted;

  const RoomLobbyExitResult({this.partyDeleted = false});
}
