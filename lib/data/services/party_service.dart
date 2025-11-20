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
}
