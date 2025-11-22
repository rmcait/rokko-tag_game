import 'dart:math';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/firebase_user_model.dart';

class PartyCodeGenerationException implements Exception {
  final String message;

  const PartyCodeGenerationException(this.message);

  @override
  String toString() => 'PartyCodeGenerationException: $message';
}

class PartyJoinException implements Exception {
  final String message;

  const PartyJoinException(this.message);

  @override
  String toString() => 'PartyJoinException: $message';
}

enum PartyMemberRole {
  pending,
  tagger,
  runner,
}

PartyMemberRole partyMemberRoleFromCode(String? code) {
  switch (code) {
    case 'TAGGER':
      return PartyMemberRole.tagger;
    case 'RUNNER':
      return PartyMemberRole.runner;
    default:
      return PartyMemberRole.pending;
  }
}

extension PartyMemberRoleCode on PartyMemberRole {
  String get code {
    switch (this) {
      case PartyMemberRole.pending:
        return 'PENDING';
      case PartyMemberRole.tagger:
        return 'TAGGER';
      case PartyMemberRole.runner:
        return 'RUNNER';
    }
  }
}

class PartyCreationResult {
  final String partyId;
  final String inviteCode;

  const PartyCreationResult({
    required this.partyId,
    required this.inviteCode,
  });
}

class PartyMemberData {
  final String userId;
  final String name;
  final PartyMemberRole role;
  final String? avatarUrl;
  final bool isReady;
  final bool isMock;

  const PartyMemberData({
    required this.userId,
    required this.name,
    required this.role,
    this.avatarUrl,
    this.isReady = false,
    this.isMock = false,
  });

  factory PartyMemberData.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final userId = data['userId'] as String? ?? doc.id;
    final name =
        data['displayName'] as String? ?? data['nickname'] as String? ?? 'Player';
    return PartyMemberData(
      userId: userId,
      name: name,
      role: partyMemberRoleFromCode(data['role'] as String?),
      avatarUrl: data['avatarUrl'] as String?,
      isReady: data['ready'] as bool? ?? false,
      isMock: data['isMock'] as bool? ?? false,
    );
  }
}

class PartyLobbyData {
  final String partyId;
  final String inviteCode;
  final PartyMemberData owner;
  final List<PartyMemberData> participants;
  final int durationMinutes;
  // ★追加: DBのステータスとゲームIDを受け取る
  final String status; 
  final String? gameId; 
  const PartyLobbyData({
    required this.partyId,
    required this.inviteCode,
    required this.owner,
    required this.participants,
    required this.durationMinutes,
    required this.status,
    this.gameId,
  });

  PartyLobbyData copyWith({
    PartyMemberData? owner,
    List<PartyMemberData>? participants,
    int? durationMinutes,
    String? status,
    String? gameId,
  }) {
    return PartyLobbyData(
      partyId: partyId,
      inviteCode: inviteCode,
      owner: owner ?? this.owner,
      participants: participants ?? this.participants,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      status: status ?? this.status,
      gameId: gameId ?? this.gameId,
    );
  }

  int get memberCount => 1 + participants.length;

  List<PartyMemberData> get allMembers => [owner, ...participants];
}

class GameSessionData {
  final String gameId;
  final String partyId;
  final String status;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? freezeUntil;
  final int durationMinutes;

  const GameSessionData({
    required this.gameId,
    required this.partyId,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.freezeUntil,
    required this.durationMinutes,
  });

  factory GameSessionData.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final startAt = (data['startAt'] as Timestamp?)?.toDate();
    final endAt = (data['endAt'] as Timestamp?)?.toDate();
    final freezeUntil = (data['freezeUntil'] as Timestamp?)?.toDate();
    return GameSessionData(
      gameId: data['gameId'] as String? ?? doc.id,
      partyId: data['partyId'] as String? ?? '',
      status: data['status'] as String? ?? 'PREPARE',
      startAt: startAt,
      endAt: endAt,
      freezeUntil: freezeUntil,
      durationMinutes: data['durationMinutes'] as int? ?? 15,
    );
  }
}

class PartyService {
  PartyService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  static const int _capacityMax = 5;

  CollectionReference<Map<String, dynamic>> get _parties =>
      _firestore.collection('parties');

  Future<PartyCreationResult> createParty({
    required UserModel owner,
    required List<LatLng> polygon,
    int durationMinutes = 15,
    String visibility = 'PRIVATE',
    String? name,
  }) async {
    final inviteCode = await _generateUniqueInviteCode();
    final docRef = _parties.doc();

    final batch = _firestore.batch();
    final polygonMaps =
        polygon.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();

    batch.set(docRef, {
      'partyId': docRef.id,
      'ownerId': owner.uid,
      'name': name ?? '${owner.displayName}のルーム',
      'capacityMax': _capacityMax,
      'status': 'WAITING',
      'durationMinutes': durationMinutes,
      'area': {'polygon': polygonMaps},
      'visibility': visibility,
      'inviteCode': inviteCode,
      'itemSeed': docRef.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final membersRef = docRef.collection('members').doc(owner.uid);
    batch.set(membersRef, {
      'memberId': owner.uid,
      'userId': owner.uid,
      'role': PartyMemberRole.pending.code,
      'ready': true,
      'displayName': owner.displayName,
      'avatarUrl': owner.photoUrl,
      'joinedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    return PartyCreationResult(
      partyId: docRef.id,
      inviteCode: inviteCode,
    );
  }

  /// Firestore からパーティ情報と参加者リストを取得する。
  /// データが存在しない場合は null を返す。
  Future<PartyLobbyData?> fetchPartyLobbyByInviteCode(String inviteCode) async {
    final snapshot = await _parties
        .where('inviteCode', isEqualTo: inviteCode)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      return null;
    }
    return _buildLobbyFromPartyDoc(snapshot.docs.first);
  }

  Future<PartyLobbyData?> fetchPartyLobbyById(String partyId) async {
    final doc = await _parties.doc(partyId).get();
    if (!doc.exists) {
      return null;
    }
    return _buildLobbyFromPartyDoc(doc);
  }

  Stream<PartyLobbyData?> watchPartyLobby(String partyId) {
    final docRef = _parties.doc(partyId);

    // Emit whenever EITHER party doc or members change, using the latest of both.
    return Stream.multi((controller) {
      DocumentSnapshot<Map<String, dynamic>>? latestParty;
      List<QueryDocumentSnapshot<Map<String, dynamic>>> latestMembers = const [];

      void emitIfReady() {
        final partySnap = latestParty;
        if (partySnap == null || !partySnap.exists) {
          controller.add(null);
          return;
        }
        controller.add(_partyLobbyFromSnapshots(partySnap, latestMembers));
      }

      final subs = <StreamSubscription<dynamic>>[];
      subs.add(docRef.snapshots().listen((partySnap) {
        latestParty = partySnap;
        emitIfReady();
      }));
      subs.add(docRef
          .collection('members')
          .orderBy('joinedAt', descending: false)
          .snapshots()
          .listen((memberSnap) {
        latestMembers = memberSnap.docs;
        emitIfReady();
      }));

      controller.onCancel = () {
        for (final s in subs) {
          s.cancel();
        }
      };
    });
  }

  Stream<GameSessionData?> watchGameSession(String gameId) {
    final docRef = _firestore.collection('gameSessions').doc(gameId);
    return docRef.snapshots().map((snap) {
      if (!snap.exists) return null;
      return GameSessionData.fromDoc(snap);
    });
  }

  Future<PartyLobbyData?> joinPartyByInviteCode({
    required String inviteCode,
    required UserModel user,
    bool seedMockMembersIfNeeded = false,
    int desiredMockCount = 0,
  }) async {
    final lobby = await fetchPartyLobbyByInviteCode(inviteCode);
    if (lobby == null) {
      return null;
    }
    if (lobby.memberCount >= _capacityMax) {
      throw const PartyJoinException('このルームは満員です');
    }

    final membersRef =
        _parties.doc(lobby.partyId).collection('members').doc(user.uid);
    final current = await membersRef.get();
    if (current.exists) {
      await membersRef.set(
        {
          'displayName': user.displayName,
          'avatarUrl': user.photoUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } else {
      await membersRef.set({
        'memberId': user.uid,
        'userId': user.uid,
        'role': PartyMemberRole.pending.code,
        'ready': false,
        'displayName': user.displayName,
        'avatarUrl': user.photoUrl,
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }

    if (seedMockMembersIfNeeded && desiredMockCount > 0) {
      await ensureMockMembers(
        lobby.partyId,
        // desiredCount: desiredMockCount,
      );
    }

    return fetchPartyLobbyById(lobby.partyId);
  }

  Future<void> ensureMockMembers(
    String partyId, {
    int desiredCount = 2,
  }) async {
    final docRef = _parties.doc(partyId);
    final membersRef = docRef.collection('members');
    final snapshot = await membersRef.get();
    final existingMembers = snapshot.docs.map(PartyMemberData.fromDoc).toList();
    final mockDocs = snapshot.docs
        .where((doc) => (doc.data()['isMock'] as bool?) ?? false)
        .toList();
    final mockCount = existingMembers.where((m) => m.isMock).length;
    final realMembers = existingMembers.length - mockCount;

    final availableSlots = (_capacityMax - realMembers).clamp(0, _capacityMax);
    final targetMockCount = availableSlots == 0
        ? 0
        : desiredCount.clamp(0, availableSlots);
    final currentMockCount = mockCount;

    final batch = _firestore.batch();
    var hasChanges = false;
    if (currentMockCount > targetMockCount) {
      final excess = currentMockCount - targetMockCount;
      for (var i = 0; i < excess && i < mockDocs.length; i++) {
        batch.delete(mockDocs[i].reference);
        hasChanges = true;
      }
    } else if (currentMockCount < targetMockCount) {
      final needed = targetMockCount - currentMockCount;
      final mockSamples = generateMockParticipants(count: needed);
      for (final mock in mockSamples) {
        final docRef = membersRef.doc();
        batch.set(docRef, {
          'memberId': docRef.id,
          'userId': docRef.id,
          'role': PartyMemberRole.pending.code,
          'ready': false,
          'displayName': mock.name,
          'avatarUrl': mock.avatarUrl,
          'joinedAt': FieldValue.serverTimestamp(),
          'isMock': true,
        });
        hasChanges = true;
      }
    }

    if (hasChanges) {
      await batch.commit();
    }
  }

  Future<void> assignRolesRandomly(String partyId) async {
    final membersSnap = await _parties
        .doc(partyId)
        .collection('members')
        .orderBy('joinedAt', descending: false)
        .get();
    if (membersSnap.docs.length < 2) {
      throw const PartyJoinException('役割を決めるには2人以上必要です');
    }

    final random = Random();
    final taggerIndex = random.nextInt(membersSnap.docs.length);
    final batch = _firestore.batch();

    for (var i = 0; i < membersSnap.docs.length; i++) {
      final doc = membersSnap.docs[i];
      final role =
          i == taggerIndex ? PartyMemberRole.tagger : PartyMemberRole.runner;
      batch.set(
        doc.reference,
        {'role': role.code},
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  List<PartyMemberData> generateMockParticipants({int count = 4}) {
    const names = [
      'Yuto',
      'Aoi',
      'Kento',
      'Mika',
      'Haruka',
      'Shun',
      'Rina',
      'Sota',
    ];
    final avatars = List<String>.generate(
      count,
      (i) => 'https://i.pravatar.cc/150?img=${i + 5}',
    );

    return List.generate(
      count,
      (index) => PartyMemberData(
        userId: 'mock_user_$index',
        name: names[index % names.length],
        role: PartyMemberRole.pending,
        avatarUrl: avatars[index],
        isMock: true,
      ),
    );
  }

  /// ルーム作成直後に Firestore へ保存される前提のロビー情報を生成。
  PartyLobbyData localLobbyDataFromOwner({
    required UserModel owner,
    required String inviteCode,
    String partyId = 'local_party',
    int durationMinutes = 15,
  }) {
    return PartyLobbyData(
      partyId: partyId,
      inviteCode: inviteCode,
      owner: PartyMemberData(
        userId: owner.uid,
        name: owner.displayName,
        role: PartyMemberRole.pending,
        avatarUrl: owner.photoUrl,
      ),
      participants: const [],
      durationMinutes: durationMinutes,
      status: 'WAITING', // ★ここを追加しました
    );
  }

  Future<PartyLobbyData?> _buildLobbyFromPartyDoc(
    DocumentSnapshot<Map<String, dynamic>> partyDoc,
  ) async {
    final membersSnap = await partyDoc.reference
        .collection('members')
        .orderBy('joinedAt', descending: false)
        .get();
    return _partyLobbyFromSnapshots(partyDoc, membersSnap.docs);
  }
  Future<String> startGame(PartyLobbyData lobby) async {
    final partyRef = _parties.doc(lobby.partyId);
    final partySnapshot = await partyRef.get();
    final partyData = partySnapshot.data();
    final polygon = _parsePolygonPoints(
      partyData?['area']?['polygon'] as List<dynamic>?,
    );
    final seed = (partyData?['itemSeed'] as String?) ?? lobby.partyId;
    final runnerItems = _generateInitialItemsForGame(
      polygon: polygon,
      seed: '$seed-runner',
      types: _runnerItemTypes,
    );
    final taggerItems = _generateInitialItemsForGame(
      polygon: polygon,
      seed: '$seed-tagger',
      types: _taggerItemTypes,
    );
    final initialItems = [...runnerItems, ...taggerItems];

    final batch = _firestore.batch();

    // 1. gameSessions ドキュメントを作成 (DB定義書 2.3)
    final gameRef = _firestore.collection('gameSessions').doc();
    final gameId = gameRef.id;

    batch.set(gameRef, {
      'gameId': gameId,
      'partyId': lobby.partyId,
      'status': 'ACTIVE',
      'startAt': FieldValue.serverTimestamp(),
      'freezeUntil': Timestamp.fromDate(
        DateTime.now().add(const Duration(seconds: 30)),
      ),
      'durationMinutes': lobby.durationMinutes,
      // area情報などはlobbyから取得して設定してください
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. 参加者を gameSessions/players にコピー（ドキュメントID = userId に固定）
    for (final member in lobby.allMembers) {
      final playerRef = gameRef.collection('players').doc(member.userId);
      batch.set(playerRef, {
        'playerId': playerRef.id,
        'userId': member.userId,
        'displayName': member.name,
        'role': member.role.code,
        'status': 'ACTIVE',
        'caught': false,
        'inside': true, // ★★★ これを追加！
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // 2.5 ゲーム開始時に初期アイテムをスポーン (database.md 参照)
    for (final item in initialItems) {
      final itemRef = gameRef.collection('items').doc(item.itemId);
      batch.set(itemRef, {
        'itemId': item.itemId,
        'type': item.type,
        'visibility': item.visibility,
        'lat': item.lat,
        'lng': item.lng,
        'spawnedAt': FieldValue.serverTimestamp(),
        'pickedBy': null,
        'state': 'AVAILABLE',
      });
    }

    // 3. parties の status を IN_PROGRESS に更新し gameId を紐付け
    // これにより StreamBuilder が反応して全員遷移する
    batch.update(partyRef, {
      'status': 'IN_PROGRESS',
      'gameId': gameId,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    return gameId;
  }

  Future<void> updateGameStatus({
    required String gameId,
    required String status,
    String? partyId,
  }) async {
    final batch = _firestore.batch();
    final gameRef = _firestore.collection('gameSessions').doc(gameId);
    batch.update(gameRef, {
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (partyId != null) {
      batch.update(_parties.doc(partyId), {
        'status': status == 'ACTIVE' ? 'IN_PROGRESS' : status == 'ABORTED' ? 'CANCELLED' : status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
  PartyLobbyData _partyLobbyFromSnapshots(
    DocumentSnapshot<Map<String, dynamic>> partyDoc,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> memberDocs,
  ) {
    final data = partyDoc.data() ?? <String, dynamic>{};
    final ownerId = data['ownerId'] as String? ?? '';
    final members = memberDocs.map(PartyMemberData.fromDoc).toList();
    final ownerMember = members.firstWhere(
      (m) => m.userId == ownerId,
      orElse: () => PartyMemberData(
        userId: ownerId.isNotEmpty ? ownerId : 'owner',
        name: 'Owner',
        role: PartyMemberRole.pending,
      ),
    );
    final participants =
        members.where((m) => m.userId != ownerMember.userId).toList();
    final duration = data['durationMinutes'] as int? ?? 15;
    final status = data['status'] as String? ?? 'WAITING';
    final gameId = data['gameId'] as String?;
    return PartyLobbyData(
      partyId: partyDoc.id,
      inviteCode: data['inviteCode'] as String? ?? '------',
      owner: ownerMember,
      participants: participants,
      durationMinutes: duration,
      status: status,
      gameId: gameId,
    );
  }

  Future<String> _generateUniqueInviteCode({int maxAttempts = 8}) async {
    final random = Random();
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final code = _randomSixDigitCode(random);
      final exists = await _inviteCodeExists(code);
      if (!exists) {
        return code;
      }
    }
    throw const PartyCodeGenerationException(
      'Failed to generate unique invite code.',
    );
  }

  Future<bool> _inviteCodeExists(String code) async {
    final snapshot =
        await _parties.where('inviteCode', isEqualTo: code).limit(1).get();
    return snapshot.docs.isNotEmpty;
  }

  String _randomSixDigitCode(Random random) =>
      (random.nextInt(900000) + 100000).toString();

  Future<void> deleteParty(String partyId) async {
    final docRef = _parties.doc(partyId);
    final membersSnap = await docRef.collection('members').get();
    final batch = _firestore.batch();
    for (final member in membersSnap.docs) {
      batch.delete(member.reference);
    }
    batch.delete(docRef);
    await batch.commit();
  }

  Future<void> updatePartyDuration(String partyId, int minutes) async {
    await _parties.doc(partyId).update({
      'durationMinutes': minutes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<LatLng>?> fetchPartyPolygon(String partyId) async {
    final doc = await _parties.doc(partyId).get();
    if (!doc.exists) return null;
    final data = doc.data();
    final poly = data?['area']?['polygon'] as List<dynamic>?;
    if (poly == null || poly.isEmpty) return null;
    final points = <LatLng>[];
    for (final p in poly) {
      final lat = (p['lat'] as num?)?.toDouble();
      final lng = (p['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        points.add(LatLng(lat, lng));
      }
    }
    return points;
  }

  List<LatLng> _parsePolygonPoints(List<dynamic>? rawPolygon) {
    if (rawPolygon == null) {
      return const [];
    }
    final points = <LatLng>[];
    for (final point in rawPolygon) {
      final lat = (point['lat'] as num?)?.toDouble();
      final lng = (point['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        points.add(LatLng(lat, lng));
      }
    }
    return points;
  }

  List<_GeneratedItem> _generateInitialItemsForGame({
    required List<LatLng> polygon,
    required String seed,
    required List<String> types,
  }) {
    final fieldPolygon = polygon.isNotEmpty ? polygon : _defaultFieldPolygon();
    final bounds = _PolygonBounds.fromPolygon(fieldPolygon);
    final random = Random(seed.hashCode);

    final items = <_GeneratedItem>[];
    for (final type in types) {
      final point = _randomPointInsidePolygon(
        random: random,
        bounds: bounds,
        polygon: fieldPolygon,
      );
      final visibility = _itemVisibilityByType[type] ?? _defaultItemVisibility;
      items.add(
        _GeneratedItem(
          itemId: _generateItemId(random),
          type: type,
          visibility: visibility,
          lat: point.latitude,
          lng: point.longitude,
        ),
      );
    }
    return items;
  }

  LatLng _randomPointInsidePolygon({
    required Random random,
    required _PolygonBounds bounds,
    required List<LatLng> polygon,
  }) {
    for (var attempt = 0; attempt < 30; attempt++) {
      final lat =
          bounds.minLat + random.nextDouble() * bounds.latDelta;
      final lng =
          bounds.minLng + random.nextDouble() * bounds.lngDelta;
      if (_isPointInsidePolygon(lat, lng, polygon)) {
        return LatLng(lat, lng);
      }
    }
    // フォールバック: 多角形の重心を使う
    return _polygonCentroid(polygon);
  }

  bool _isPointInsidePolygon(double lat, double lng, List<LatLng> polygon) {
    var inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].latitude;
      final yi = polygon[i].longitude;
      final xj = polygon[j].latitude;
      final yj = polygon[j].longitude;

      final intersect = ((yi > lng) != (yj > lng)) &&
          (lat <
              (xj - xi) * (lng - yi) / ((yj - yi) == 0 ? 1e-9 : (yj - yi)) +
                  xi);
      if (intersect) {
        inside = !inside;
      }
    }
    return inside;
  }

  LatLng _polygonCentroid(List<LatLng> polygon) {
    var latSum = 0.0;
    var lngSum = 0.0;
    for (final point in polygon) {
      latSum += point.latitude;
      lngSum += point.longitude;
    }
    final count = polygon.isEmpty ? 1 : polygon.length;
    return LatLng(latSum / count, lngSum / count);
  }

  List<LatLng> _defaultFieldPolygon() {
    const baseLat = 35.681236;
    const baseLng = 139.767125;
    const delta = 0.0005;
    return [
      const LatLng(baseLat, baseLng),
      const LatLng(baseLat, baseLng + delta),
      const LatLng(baseLat + delta, baseLng + delta),
      const LatLng(baseLat + delta, baseLng),
    ];
  }

  String _generateItemId(Random random) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final buffer = StringBuffer('itm_');
    for (var i = 0; i < 10; i++) {
      buffer.write(chars[random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }
}

const _defaultItemVisibility = 'RUNNER';

const List<String> _runnerItemTypes = [
  'SEE_TAGGER',
  'FAKE_LOCATION',
  'FREEZE_TAGGER',
];

const List<String> _taggerItemTypes = [
  'TRAP',
  'FAKE_LOCATION_TAGGER',
];

const Map<String, String> _itemVisibilityByType = {
  'SEE_TAGGER': 'RUNNER',
  'FAKE_LOCATION': 'RUNNER',
  'FREEZE_TAGGER': 'RUNNER',
  'TRAP': 'TAGGER',
  'FREEZE_ALL': 'TAGGER',
  'FAKE_LOCATION_TAGGER': 'TAGGER',
};

class _GeneratedItem {
  final String itemId;
  final String type;
  final String visibility;
  final double lat;
  final double lng;

  const _GeneratedItem({
    required this.itemId,
    required this.type,
    required this.visibility,
    required this.lat,
    required this.lng,
  });
}

class _PolygonBounds {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const _PolygonBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  double get latDelta => (maxLat - minLat).abs().clamp(1e-6, double.infinity);
  double get lngDelta => (maxLng - minLng).abs().clamp(1e-6, double.infinity);

  factory _PolygonBounds.fromPolygon(List<LatLng> polygon) {
    double minLat = polygon.first.latitude;
    double maxLat = polygon.first.latitude;
    double minLng = polygon.first.longitude;
    double maxLng = polygon.first.longitude;

    for (final point in polygon) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return _PolygonBounds(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );
  }
}
