import 'package:cloud_firestore/cloud_firestore.dart';

class GameService {
  GameService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// プレイヤーの位置を gameSessions/{gameId}/players/{playerId} に保存
  Future<void> updatePlayerLocation({
    required String gameId,
    required String playerId,
    required double lat,
    required double lng,
    required bool inside,
  }) async {
    final ref = _firestore
        .collection('gameSessions')
        .doc(gameId)
        .collection('players')
        .doc(playerId);

    await ref.set(
      {
        'lastLocation': GeoPoint(lat, lng),
        'insideField': inside,
        'lastUpdateAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}