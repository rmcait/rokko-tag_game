import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FieldArea {
  final String id;
  final String name;
  final List<LatLng> vertices;
  final DateTime? createdAt;

  FieldArea({
    required this.id,
    required this.name,
    required this.vertices,
    required this.createdAt,
  });

  factory FieldArea.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final List<dynamic> rawVertices = data['vertices'] ?? [];

    return FieldArea(
      id: doc.id,
      name: data['name'] as String? ?? '名無しフィールド',
      vertices: rawVertices
          .whereType<GeoPoint>()
          .map((g) => LatLng(g.latitude, g.longitude))
          .toList(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

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

  /// 履歴一覧（リアルタイム）
  Stream<List<FieldArea>> watchFields() {
    return _db
        .collection('fields')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) => FieldArea.fromDoc(doc)).toList(),
        );
  }
}