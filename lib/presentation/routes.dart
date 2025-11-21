import 'package:flutter/material.dart';

import '../data/services/party_service.dart';
import 'pages/home/home_page.dart';
import 'pages/login/login_page.dart';
import 'pages/map/map_page.dart';
import 'pages/room/room_join_page.dart';
import 'pages/room/room_game_page.dart';
import 'pages/room/room_lobby_page.dart';



class AppRoutes {
  static const home = '/';
  static const login = '/login';
  static const map = '/map';
  static const joinRoom = '/join-room';
  static const roomLobby = '/room-lobby';
  static const roomGame = '/room-game';
}

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.login:
        return MaterialPageRoute<void>(
          builder: (_) => const LoginPage(),
        );
      case AppRoutes.map:
        final args = settings.arguments as MapPageArgs?;
        return MaterialPageRoute<void>(
          builder: (_) => MapPage(
            initialPoints: args?.initialPoints,
            isEditing: args?.isEditing ?? false,
            roomCreation: args?.roomCreation,
          ),
        );
      case '/home':
        // Accept '/home' as an alias for the home route
        return MaterialPageRoute<void>(
          builder: (_) => const HomePage(),
        );
      case AppRoutes.joinRoom:
        return MaterialPageRoute<void>(
          builder: (_) => const RoomJoinPage(),
        );
      case AppRoutes.roomLobby:
        final args = settings.arguments;
        final roomArgs = args is RoomLobbyPageArgs
            ? args
            : RoomLobbyPageArgs(
                lobby: PartyLobbyData(
                  partyId: 'local',
                  inviteCode: '------',
                  owner: const PartyMemberData(
                    userId: 'owner',
                    name: 'Owner',
                    role: PartyMemberRole.pending,
                  ),
                  participants: const [],
                  durationMinutes: 15,
                  status: 'WAITING', // ★追加
                ),
                currentUserId: 'owner',
              );
        return MaterialPageRoute<void>(
          builder: (_) => RoomLobbyPage(args: roomArgs),
        );
      case AppRoutes.roomGame:
        final args = settings.arguments;
        final gameArgs = args is RoomGamePageArgs
            ? args
            : RoomGamePageArgs(
                lobby: const PartyLobbyData(
                  partyId: 'local',
                  inviteCode: '------',
                  owner: PartyMemberData(
                    userId: 'owner',
                    name: 'Owner',
                    role: PartyMemberRole.pending,
                  ),
                  participants: [],
                  durationMinutes: 15,
                  status: 'IN_PROGRESS', // ★追加
                ),
                currentUserId: 'owner',
                gameId: 'local-game',
              );
        return MaterialPageRoute<void>(
          builder: (_) => RoomGamePage(args: gameArgs),
        );
      case AppRoutes.home:
      default:
        return MaterialPageRoute<void>(
          builder: (_) => const HomePage(),
        );
    }
  }
}
