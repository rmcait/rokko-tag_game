import '../../../data/services/party_service.dart';
import 'room_lobby_page.dart';

RoomLobbyPageArgs lobbyArgsFromPartyLobby(PartyLobbyData data) {
  return RoomLobbyPageArgs(
    roomCode: data.inviteCode,
    owner: RoomLobbyMember(
      name: data.owner.name,
      avatarUrl: data.owner.avatarUrl,
    ),
    participants: data.participants
        .map(
          (member) => RoomLobbyMember(
            name: member.name,
            avatarUrl: member.avatarUrl,
          ),
        )
        .toList(),
  );
}
