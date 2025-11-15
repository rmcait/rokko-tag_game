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
  final String role;
  final String? avatarUrl;

  const PartyMemberData({
    required this.userId,
    required this.name,
    required this.role,
    this.avatarUrl,
  });

  factory PartyMemberData.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final userId = data['userId'] as String? ?? doc.id;
    final name = data['displayName'] as String? ?? data['nickname'] as String? ?? 'Player';
    return PartyMemberData(
      userId: userId,
      name: name,
      role: data['role'] as String? ?? 'PENDING',
      avatarUrl: data['avatarUrl'] as String?,
    );
  }
}

class PartyLobbyData {
  final String partyId;
  final String inviteCode;
  final PartyMemberData owner;
  final List<PartyMemberData> participants;

  const PartyLobbyData({
    required this.partyId,
    required this.inviteCode,
    required this.owner,
    required this.participants,
  });

  PartyLobbyData copyWith({
    PartyMemberData? owner,
    List<PartyMemberData>? participants,
  }) {
    return PartyLobbyData(
      partyId: partyId,
      inviteCode: inviteCode,
      owner: owner ?? this.owner,
      participants: participants ?? this.participants,
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
      'role': 'OWNER',
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
    final snapshot =
        await _parties.where('inviteCode', isEqualTo: inviteCode).limit(1).get();
    if (snapshot.docs.isEmpty) {
      return null;
    }

    final partyDoc = snapshot.docs.first;
    final data = partyDoc.data();
    final ownerId = data['ownerId'] as String? ?? '';

    final membersSnap = await partyDoc.reference
        .collection('members')
        .orderBy('joinedAt', descending: false)
        .get();
    final members = membersSnap.docs
        .map(PartyMemberData.fromDoc)
        .toList();

    final ownerMember = members.firstWhere(
      (m) => m.userId == ownerId,
      orElse: () => PartyMemberData(
        userId: ownerId.isNotEmpty ? ownerId : 'owner',
        name: 'Owner',
        role: 'OWNER',
      ),
    );

    final participants = members.where((m) => m.userId != ownerMember.userId).toList();

    return PartyLobbyData(
      partyId: partyDoc.id,
      inviteCode: inviteCode,
      owner: ownerMember,
      participants: participants,
    );
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
        role: index == 0 ? 'TAGGER' : 'RUNNER',
        avatarUrl: avatars[index],
      ),
    );
  }

  /// モック参加者のみを付与するユーティリティ。
  PartyLobbyData withMockParticipants(
    PartyLobbyData lobby, {
    int count = 4,
  }) {
    return lobby.copyWith(
      participants: generateMockParticipants(count: count),
    );
  }

  /// ルーム作成直後に Firestore へ保存される前提のロビー情報を生成。
  PartyLobbyData localLobbyDataFromOwner({
    required UserModel owner,
    required String inviteCode,
    String partyId = 'local_party',
  }) {
    return PartyLobbyData(
      partyId: partyId,
      inviteCode: inviteCode,
      owner: PartyMemberData(
        userId: owner.uid,
        name: owner.displayName,
        role: 'OWNER',
        avatarUrl: owner.photoUrl,
      ),
      participants: const [],
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
}
