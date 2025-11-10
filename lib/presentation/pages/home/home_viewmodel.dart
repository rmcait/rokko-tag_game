import 'package:flutter/material.dart';

import '../../../data/repository.dart';
import '../../../data/services/api_service.dart';
import '../../../domain/entities.dart';

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    SampleRepository? repository,
  }) : _repository = repository ?? SampleRepository(ApiService());

  final SampleRepository _repository;

  SampleEntity? _welcomeMessage;
  bool _isLoading = false;

  SampleEntity? get welcomeMessage => _welcomeMessage;
  bool get isLoading => _isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    _welcomeMessage = await _repository.loadWelcomeMessage();
    _isLoading = false;
    notifyListeners();
  }
}
