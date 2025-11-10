<<<<<<< HEAD
/// ユーザー情報のデータモデル
class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
  });

  /// Firebase User から UserModel を生成
  factory UserModel.fromFirebaseUser(dynamic firebaseUser) {
    return UserModel(
      uid: firebaseUser.uid,
      email: firebaseUser.email ?? '',
      displayName: firebaseUser.displayName ?? 'ゲスト',
      photoUrl: firebaseUser.photoURL,
    );
  }

  /// Firestore用のMapに変換
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
    };
  }

  /// FirestoreのMapからUserModelを生成
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      displayName: map['displayName'] ?? 'ゲスト',
      photoUrl: map['photoUrl'],
    );
=======
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
>>>>>>> 9b9f9c963f02aec80ef4b23e24e2d55f611c784e
  }
}
