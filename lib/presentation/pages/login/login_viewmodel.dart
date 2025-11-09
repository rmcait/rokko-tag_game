import 'package:flutter/material.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/auth_service.dart';

/// ログイン画面のViewModel
class LoginViewModel extends ChangeNotifier {
  final AuthService _authService;

  LoginViewModel(this._authService);

  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Googleログイン処理
  Future<UserModel?> signInWithGoogle() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signInWithGoogle();
      _isLoading = false;
      notifyListeners();
      return user;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'ログインに失敗しました: ${e.toString()}';
      notifyListeners();
      return null;
    }
  }

  /// 匿名ログイン処理
  Future<UserModel?> signInAnonymously() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signInAnonymously();
      _isLoading = false;
      notifyListeners();
      return user;
    } catch (e) {
      _isLoading = false;
      _errorMessage = '匿名ログインに失敗しました: ${e.toString()}';
      notifyListeners();
      return null;
    }
  }

  /// エラーメッセージをクリア
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
