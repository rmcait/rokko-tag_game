import '../../domain/entities.dart';

/// API などのレスポンスをアプリ内部の Entity に変換するモデル。
class SampleModel {
  const SampleModel({required this.message});

  final String message;

  SampleEntity toEntity() => SampleEntity(message: message);

  factory SampleModel.fromJson(Map<String, dynamic> json) {
    return SampleModel(message: json['message'] as String? ?? 'hello');
  }
}
