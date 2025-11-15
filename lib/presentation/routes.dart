import 'package:flutter/material.dart';

import 'pages/home/home_page.dart';
import 'pages/login/login_page.dart';
import 'pages/map/map_page.dart';
import 'pages/room/room_join_page.dart';
import 'pages/room/room_lobby_page.dart';

class AppRoutes {
  static const home = '/';
  static const login = '/login';
  static const map = '/map';
  static const joinRoom = '/join-room';
  static const roomLobby = '/room-lobby';
}

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.login:
        return MaterialPageRoute<void>(
          builder: (_) => const LoginPage(),
        );
      case AppRoutes.map:
        final args = settings.arguments;
        if (args is MapPageArgs) {
          return MaterialPageRoute<void>(
            builder: (_) => MapPage(
              initialPoints: args.initialPoints,
              isEditing: args.isEditing,
              roomCreation: args.roomCreation,
            ),
          );
        }
        return MaterialPageRoute<void>(
          builder: (_) => const MapPage(),
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
            : const RoomLobbyPageArgs(
                roomCode: '------',
                owner: RoomLobbyMember(name: 'Owner'),
              );
        return MaterialPageRoute<void>(
          builder: (_) => RoomLobbyPage(args: roomArgs),
        );
      case AppRoutes.home:
      default:
        return MaterialPageRoute<void>(
          builder: (_) => const HomePage(),
        );
    }
  }
}
