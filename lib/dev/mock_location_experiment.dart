import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/services/party_service.dart';

/// ランナーの位置を擬似的に移動させ、Firestore の `lastLocation` を更新した直後に
/// 近傍アイテムの自動取得ロジックを呼び出すための簡易モック。
///
/// `simulateMovement` にパスとゲーム/プレイヤー ID を渡すだけで、
/// - `players/{playerId}.lastLocation` を順番に更新
/// - 各地点で `PartyService.pickupNearbyItem` を呼び出し
/// という処理を行います。
class MockLocationExperiment {
  MockLocationExperiment({
    FirebaseFirestore? firestore,
    PartyService? partyService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _partyService = partyService ?? PartyService(firestore: firestore);

  final FirebaseFirestore _firestore;
  final PartyService _partyService;

  /// 擬似的にプレイヤーを移動させる。
  ///
  /// [path] に与えた地点を順番に通過し、各地点で Firestore の `lastLocation` を更新する。
  /// 位置更新後すぐに `_partyService.pickupNearbyItem` を呼ぶため、
  /// 実際のクライアントから自動取得ロジックを呼び出す際の動作確認に利用できる。
  Future<void> simulateMovement({
    required String gameId,
    required String playerId,
    required List<LatLng> path,
    Duration interval = const Duration(seconds: 1),
    double pickupRadiusMeters = 5,
  }) async {
    if (path.isEmpty) return;
    for (final point in path) {
      await _updatePlayerLocation(gameId: gameId, playerId: playerId, point: point);
      final picked = await _partyService.pickupNearbyItem(
        gameId: gameId,
        playerId: playerId,
        playerLatLng: point,
        radiusMeters: pickupRadiusMeters,
        allowedTypes: const {'FAKE_LOCATION', 'FREEZE_TAGGER', 'SEE_TAGGER'},
      );
      if (picked != null) {
        // ignore: avoid_print
        print(
          '[MockLocationExperiment] Picked ${picked.type} (${picked.itemId}) at '
          '${point.latitude}, ${point.longitude}',
        );
      } else {
        // ignore: avoid_print
        print(
          '[MockLocationExperiment] Move to ${point.latitude}, ${point.longitude} '
          '-> no item within $pickupRadiusMeters m',
        );
      }
      if (interval > Duration.zero) {
        await Future.delayed(interval);
      }
    }
  }

  Future<void> _updatePlayerLocation({
    required String gameId,
    required String playerId,
    required LatLng point,
  }) async {
    final playerRef = _firestore.collection('gameSessions').doc(gameId).collection('players').doc(playerId);
    await playerRef.update({
      'lastLocation': GeoPoint(point.latitude, point.longitude),
      'lastUpdateAt': FieldValue.serverTimestamp(),
      'movementNoise': _mockNoise(),
    });
  }

  double _mockNoise() {
    final rand = Random();
    return (rand.nextDouble() * 2 - 1) * 0.5;
  }
}
