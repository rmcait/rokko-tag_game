import '../domain/entities.dart';
import 'services/firestore_user_service.dart';

/// Firestore 上のユーザーデータを扱うリポジトリ。
class UserRepository {
  UserRepository(this._userService);

  final FirestoreUserService _userService;

  Future<UserEntity?> fetchLatestUserAndTouch() async {
    final model = await _userService.fetchSampleUser();
    if (model == null) {
      return null;
    }
    await _userService.touchUser(model.userId);
    return model.toEntity();
  }
}
