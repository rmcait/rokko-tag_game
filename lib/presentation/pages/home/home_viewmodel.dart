import 'package:flutter/material.dart';

import '../../../data/repository.dart';
import '../../../data/services/firestore_user_service.dart';
import '../../../domain/entities.dart';

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    UserRepository? repository,
  }) : _repository = repository ?? UserRepository(FirestoreUserService());

  final UserRepository _repository;

  UserEntity? _user;
  bool _isLoading = false;

  UserEntity? get user => _user;
  bool get isLoading => _isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    _user = await _repository.fetchLatestUserAndTouch();
    _isLoading = false;
    notifyListeners();
  }
}
