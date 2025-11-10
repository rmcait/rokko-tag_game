import 'dart:async';

import '../../core/constants/app_constants.dart';

/// 外部 API のモック。実際は Dio や http パッケージで置き換える。
class ApiService {
  Future<Map<String, dynamic>> fetchWelcomeMessage() async {
    await Future.delayed(AppConstants.mockApiDelay);
    return {'message': 'ようこそ Tag Game!'};
  }
}
