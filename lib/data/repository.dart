import '../domain/entities.dart';
import 'models/sample_model.dart';
import 'services/api_service.dart';

/// データ取得の統一窓口。
class SampleRepository {
  SampleRepository(this._apiService);

  final ApiService _apiService;

  Future<SampleEntity> loadWelcomeMessage() async {
    final response = await _apiService.fetchWelcomeMessage();
    return SampleModel.fromJson(response).toEntity();
  }
}
