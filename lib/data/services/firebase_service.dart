import 'package:firebase_auth/firebase_auth.dart';

/// Firebase 関連の操作をまとめるサービス。ここでは認証状態だけを監視。
class FirebaseService {
  Stream<User?> authStateChanges() => FirebaseAuth.instance.authStateChanges();
}
