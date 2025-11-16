import '../../../data/services/party_service.dart';
import 'room_lobby_page.dart';

RoomLobbyPageArgs lobbyArgsFromPartyLobby({
  required PartyLobbyData data,
  required String currentUserId,
  bool allowFieldReselect = false,
  bool deletePartyOnExit = false,
  bool promptDurationSelection = false,
}) {
  return RoomLobbyPageArgs(
    lobby: data,
    currentUserId: currentUserId,
    allowFieldReselect: allowFieldReselect,
    deletePartyOnExit: deletePartyOnExit,
    promptDurationSelection: promptDurationSelection,
  );
}
