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
  }
}
