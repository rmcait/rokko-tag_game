import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities.dart';

class UserModel {
  const UserModel({
    required this.userId,
    required this.googleUid,
    required this.displayName,
    required this.avatarUrl,
    required this.status,
    required this.fcmToken,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return UserModel(
      userId: data['userId'] as String? ?? doc.id,
      googleUid: data['googleUid'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      avatarUrl: data['avatarUrl'] as String? ?? '',
      status: data['status'] as String? ?? 'UNKNOWN',
      fcmToken: data['fcmToken'] as String? ?? '',
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
    );
  }

  final String userId;
  final String googleUid;
  final String displayName;
  final String avatarUrl;
  final String status;
  final String fcmToken;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserEntity toEntity() => UserEntity(
        userId: userId,
        googleUid: googleUid,
        displayName: displayName,
        avatarUrl: avatarUrl,
        status: status,
        fcmToken: fcmToken,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  static DateTime? _parseTimestamp(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }
}