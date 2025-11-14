// lib/data/services/field_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FieldService {
  FieldService._();
  static final FieldService _instance = FieldService._();
  factory FieldService() => _instance;

  final _db = FirebaseFirestore.instance;

  /// フィールドを新規作成して保存
  Future<String> createField({
    required List<LatLng> vertices,
    String? ownerUid,      // 必要なら後で使う
    String? name,          // TODO: フィールド名を付けたくなったら
  }) async {
    final geoPoints =
        vertices.map((p) => GeoPoint(p.latitude, p.longitude)).toList();

    final docRef = _db.collection('fields').doc(); // ← rooms ではなく fields

    await docRef.set({
      'vertices': geoPoints,
      'ownerUid': ownerUid,
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return docRef.id;
  }
}