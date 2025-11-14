import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FieldService {
  FieldService._();
  static final FieldService _instance = FieldService._();
  factory FieldService() => _instance;

  final _db = FirebaseFirestore.instance;

  /// 共通の fields コレクションにフィールド保存
  Future<String> createField({
    required String name,
    required List<LatLng> vertices,
    String? createdBy, // 後でユーザー別にしたくなったとき用（今はなくてもOK）
  }) async {
    final geoPoints =
        vertices.map((p) => GeoPoint(p.latitude, p.longitude)).toList();

    final docRef = _db.collection('fields').doc();

    await docRef.set({
      'name': name,
      'vertices': geoPoints,
      'createdAt': FieldValue.serverTimestamp(),
      if (createdBy != null) 'createdBy': createdBy,
    });

    return docRef.id;
  }

  /// 履歴表示用：今は全部取る（後でユーザーごとに絞り込み可能）
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchFields() async {
    final snap = await _db
        .collection('fields')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs;
  }
}