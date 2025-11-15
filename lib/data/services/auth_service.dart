import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/firebase_user_model.dart';
import 'firestore_user_service.dart';

/// 認証サービス
/// Firebase AuthとGoogle Sign-Inを管理
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirestoreUserService _userService = FirestoreUserService();

  /// 現在のユーザーを取得
  User? get currentUser => _auth.currentUser;

  /// ユーザーの認証状態を監視
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// 現在のユーザー情報をUserModelで取得
  UserModel? get currentUserModel {
    final user = currentUser;
    if (user == null) return null;
    return UserModel.fromFirebaseUser(user);
  }

  /// Googleアカウントでサインイン
  Future<UserModel?> signInWithGoogle() async {
    try {
      // Googleサインインを開始
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // ユーザーがキャンセルした場合
        return null;
      }

      // Google認証情報を取得
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Firebaseの認証情報を作成
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Firebaseにサインイン
      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      // UserModelを返す
      if (userCredential.user != null) {
        final userModel = UserModel.fromFirebaseUser(userCredential.user!);
        await _userService.syncFromAuthUser(userModel);
        return userModel;
      }

      return null;
    } catch (e) {
      debugPrint('Googleサインインエラー: $e');
      rethrow;
    }
  }

  /// 匿名でサインイン
  Future<UserModel?> signInAnonymously() async {
    try {
      final UserCredential userCredential = await _auth.signInAnonymously();

      if (userCredential.user != null) {
        final userModel = UserModel.fromFirebaseUser(userCredential.user!);
        await _userService.syncFromAuthUser(userModel);
        return userModel;
      }

      return null;
    } catch (e) {
      debugPrint('匿名サインインエラー: $e');
      rethrow;
    }
  }

  /// サインアウト
  Future<void> signOut() async {
    try {
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
    } catch (e) {
      debugPrint('サインアウトエラー: $e');
      rethrow;
    }
  }
}
