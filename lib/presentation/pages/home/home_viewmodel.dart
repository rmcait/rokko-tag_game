import 'package:flutter/material.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/auth_service.dart';

/// ホーム画面のViewModel
class HomeViewModel extends ChangeNotifier {
  final AuthService _authService;

  HomeViewModel(this._authService);

  /// 現在のユーザー情報を取得
  UserModel? get currentUser => _authService.currentUserModel;

  /// サインアウト処理
  Future<void> signOut() async {
    try {
      await _authService.signOut();
      notifyListeners();
    } catch (e) {
      print('サインアウトエラー: $e');
      rethrow;
    }
  }
}
