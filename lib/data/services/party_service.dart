import 'dart:math';

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

class GameItem {
  final String itemId;
  final String type;
  final String visibility;
  final double lat;
  final double lng;
  final String state;
  final String? pickedBy;
  final Timestamp? spawnedAt;

  GameItem({
    required this.itemId,
    required this.type,
    required this.visibility,
    required this.lat,
    required this.lng,
    required this.state,
    this.pickedBy,
    this.spawnedAt,
  });

  factory GameItem.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return GameItem(
      itemId: d['itemId'] as String? ?? doc.id,
      type: d['type'] as String? ?? 'UNKNOWN',
      visibility: d['visibility'] as String? ?? 'RUNNER',
      lat: (d['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (d['lng'] as num?)?.toDouble() ?? 0.0,
      state: d['state'] as String? ?? 'AVAILABLE',
      pickedBy: d['pickedBy'] as String?,
      spawnedAt: d['spawnedAt'] as Timestamp?,
    );
  }
}

class PartyLobbyData {
  final String partyId;
  final String inviteCode;
  final PartyMemberData owner;
  final List<PartyMemberData> participants;
  final int durationMinutes;

  const PartyLobbyData({
    required this.partyId,
    required this.inviteCode,
    required this.owner,
    required this.participants,
    required this.durationMinutes,
  });

  PartyLobbyData copyWith({
    PartyMemberData? owner,
    List<PartyMemberData>? participants,
    int? durationMinutes,
  }) {
    return PartyLobbyData(
      partyId: partyId,
      inviteCode: inviteCode,
      owner: owner ?? this.owner,
      participants: participants ?? this.participants,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }

  int get memberCount => 1 + participants.length;

  List<PartyMemberData> get allMembers => [owner, ...participants];
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
    return docRef.snapshots().asyncExpand((partySnap) {
      if (!partySnap.exists) {
        return Stream.value(null);
      }
      return docRef
          .collection('members')
          .orderBy('joinedAt', descending: false)
          .snapshots()
          .map(
            (memberSnap) =>
                _partyLobbyFromSnapshots(partySnap, memberSnap.docs),
          );
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
        desiredCount: desiredMockCount,
      );
    }

    return fetchPartyLobbyById(lobby.partyId);
  }

  Future<void> ensureMockMembers(
    String partyId, {
    int desiredCount = 3,
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
    return PartyLobbyData(
      partyId: partyDoc.id,
      inviteCode: data['inviteCode'] as String? ?? '------',
      owner: ownerMember,
      participants: participants,
      durationMinutes: duration,
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

  /// Start a game session for the given party.
  /// Creates a `gameSessions/{gameId}` document and populates
  /// `gameSessions/{gameId}/items` based on the party's `itemSeed`.
  /// This runs client-side (no Cloud Functions) and is intended
  /// for local/emulator use or when server-side logic isn't required.
  Future<String> startGame(String partyId, {int itemCount = 8}) async {
    final partyRef = _parties.doc(partyId);
    final partySnap = await partyRef.get();
    if (!partySnap.exists) {
      throw PartyJoinException('Party not found');
    }

    final partyData = partySnap.data() ?? <String, dynamic>{};
    final itemSeed = partyData['itemSeed'] as String? ?? partyRef.id;
    final durationMinutes = partyData['durationMinutes'] as int? ?? 15;
    final area = partyData['area'] as Map<String, dynamic>? ?? {};

    final gameRef = _firestore.collection('gameSessions').doc();

    final now = DateTime.now().toUtc();
    final freezeUntil = Timestamp.fromDate(now.add(const Duration(seconds: 30)));

    final gameDoc = {
      'gameId': gameRef.id,
      'partyId': partyId,
      'status': 'PREPARE',
      'startAt': FieldValue.serverTimestamp(),
      'endAt': null,
      'freezeUntil': freezeUntil,
      'durationMinutes': durationMinutes,
      'area': area,
      'gaugeThreshold': 100,
      'listenDurationSeconds': 3,
      'movementSampleWindow': 5,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = _firestore.batch();
    batch.set(gameRef, gameDoc);

    // Generate deterministic items based on seed
    final polygon = (area['polygon'] as List<dynamic>?)
            ?.map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
            .toList() ??
        [];

    final rand = Random(_stableHash(itemSeed));

    const itemTypes = ['SEE_TAGGER', 'FREEZE_TAGGER', 'FAKE_LOCATION', 'TRAP', 'FAKE_LOCATION_TAGGER', 'SEE_RUNNER'];
    for (final type in itemTypes) {
      // sample a point inside polygon if possible, otherwise random bbox
      LatLng pos;
      if (polygon.isNotEmpty) {
        pos = _samplePointInPolygon(polygon, rand);
      } else {
        pos = LatLng(35.0 + rand.nextDouble(), 135.0 + rand.nextDouble());
      }

      final itemRef = gameRef.collection('items').doc();
      final visibility = rand.nextBool() ? 'TAGGER' : 'RUNNER';

      batch.set(itemRef, {
        'itemId': itemRef.id,
        'type': type,
        'visibility': visibility,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'spawnedAt': FieldValue.serverTimestamp(),
        'pickedBy': null,
        'state': 'AVAILABLE',
      });
    }

    // Create players subcollection based on party members
    final membersSnap = await partyRef.collection('members').get();
    for (final m in membersSnap.docs) {
      final mdata = m.data();
      final playerRef = gameRef.collection('players').doc();
      final roleCode = (mdata['role'] as String?) ?? 'PENDING';
      batch.set(playerRef, {
        'playerId': playerRef.id,
        'userId': mdata['userId'] as String? ?? m.id,
        'role': roleCode,
        'status': 'ACTIVE',
        'gauge': 0,
        'cooldowns': <String, dynamic>{},
        'items': <String, dynamic>{},
        'lastLocation': null,
        'lastUpdateAt': null,
      });
    }

    // update party to reference game and mark in-progress
    batch.update(partyRef, {
      'gameId': gameRef.id,
      'status': 'IN_PROGRESS',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    return gameRef.id;
  }

  /// Watch items for a game session.
  Stream<List<GameItem>> watchGameItems(String gameId) {
    final itemsRef = _firestore.collection('gameSessions').doc(gameId).collection('items');
    return itemsRef.snapshots().map((snap) =>
        snap.docs.map((d) => GameItem.fromDoc(d)).toList(growable: false));
  }

  Future<String?> findPlayerIdByUser(String gameId, String userId) async {
    final playersRef = _firestore.collection('gameSessions').doc(gameId).collection('players');
    final snap = await playersRef.where('userId', isEqualTo: userId).limit(1).get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    final data = doc.data();
    return data['playerId'] as String? ?? doc.id;
  }

  /// Attempt to pick up an item for a player.
  ///
  /// This performs a transaction that:
  /// - verifies the item exists and is `AVAILABLE`
  /// - sets `state` -> `PICKED`, `pickedBy` -> `playerId`, `pickedAt` -> serverTimestamp
  /// - updates the player's `items` map to include the picked item (by itemId)
  /// - writes an `events` entry `ITEM_PICKED`
  ///
  /// Note: `playerId` must be the document id under `gameSessions/{gameId}/players/{playerId}`.
  Future<bool> pickupItem({
    required String gameId,
    required String itemId,
    required String playerId,
  }) async {
    final gameRef = _firestore.collection('gameSessions').doc(gameId);
    final itemRef = gameRef.collection('items').doc(itemId);
    final playerRef = gameRef.collection('players').doc(playerId);

    try {
      await _firestore.runTransaction((tx) async {
        final itemSnap = await tx.get(itemRef);
        if (!itemSnap.exists) {
          throw Exception('item-not-found');
        }
        final itemData = itemSnap.data()!;
        final state = itemData['state'] as String? ?? 'AVAILABLE';
        if (state != 'AVAILABLE') {
          throw Exception('item-not-available');
        }

        // mark item as picked
        tx.update(itemRef, {
          'state': 'PICKED',
          'pickedBy': playerId,
          'pickedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // update player's items map (keyed by itemId)
        final playerSnap = await tx.get(playerRef);
        if (!playerSnap.exists) {
          throw Exception('player-not-found');
        }
        final playerData = playerSnap.data()!;
        final existing = Map<String, dynamic>.from(playerData['items'] as Map<String, dynamic>? ?? {});
        final itemType = itemData['type'] as String? ?? 'UNKNOWN';
        final prev = existing[itemId] as Map<String, dynamic>?;
        final prevCount = prev != null ? (prev['count'] as int? ?? 0) : 0;
        existing[itemId] = {
          'type': itemType,
          'count': prevCount + 1,
          'pickedAt': FieldValue.serverTimestamp(),
        };

        tx.update(playerRef, {
          'items': existing,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // write event
        final eventsRef = gameRef.collection('events').doc();
        tx.set(eventsRef, {
          'eventId': eventsRef.id,
          'type': 'ITEM_PICKED',
          'payload': {
            'itemId': itemId,
            'playerId': playerId,
            'itemType': itemType,
          },
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
      return true;
    } catch (e) {
      print('pickupItem failed: $e');
      return false;
    }
  }

  int _stableHash(String s) {
    // FNV-1a 32-bit
    var hash = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      hash ^= s.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  LatLng _samplePointInPolygon(List<LatLng> poly, Random rand) {
    // compute bbox
    var minLat = poly.first.latitude;
    var maxLat = poly.first.latitude;
    var minLng = poly.first.longitude;
    var maxLng = poly.first.longitude;
    for (final p in poly) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    for (var tries = 0; tries < 50; tries++) {
      final lat = minLat + rand.nextDouble() * (maxLat - minLat);
      final lng = minLng + rand.nextDouble() * (maxLng - minLng);
      if (_pointInPolygon(LatLng(lat, lng), poly)) {
        return LatLng(lat, lng);
      }
    }

    // fallback: return center
    return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    // ray-casting algorithm
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].latitude, yi = polygon[i].longitude;
      final xj = polygon[j].latitude, yj = polygon[j].longitude;

      final intersect = ((yi > point.longitude) != (yj > point.longitude)) &&
          (point.latitude < (xj - xi) * (point.longitude - yi) / (yj - yi + 0.0) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}
