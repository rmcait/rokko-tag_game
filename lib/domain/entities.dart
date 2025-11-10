class UserEntity {
  const UserEntity({
    required this.userId,
    required this.googleUid,
    required this.displayName,
    required this.avatarUrl,
    required this.status,
    required this.fcmToken,
    required this.createdAt,
    required this.updatedAt,
  });

  final String userId;
  final String googleUid;
  final String displayName;
  final String avatarUrl;
  final String status;
  final String fcmToken;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}
