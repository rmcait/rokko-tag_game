import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tag_game/data/services/field_service.dart';

class FieldPreviewPage extends StatelessWidget {
  final FieldArea field;

  const FieldPreviewPage({super.key, required this.field});

  @override
  Widget build(BuildContext context) {
    final center = _calculateCenter(field.vertices);

    final polygon = Polygon(
      polygonId: const PolygonId('preview'),
      points: field.vertices + [field.vertices.first],
      strokeColor: Colors.deepPurple,
      strokeWidth: 2,
      fillColor: Colors.deepPurple.withOpacity(0.2),
    );

    final markers = field.vertices.asMap().entries.map((e) {
      return Marker(
        markerId: MarkerId("p${e.key}"),
        position: e.value,
        infoWindow: InfoWindow(title: "頂点 ${e.key + 1}"),
      );
    }).toSet();

    return Scaffold(
      appBar: AppBar(
        title: Text(field.name),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: center,
          zoom: 16,
        ),
        polygons: {polygon},
        markers: markers,
        myLocationEnabled: false,
      ),
    );
  }

  /// 中心点を簡易計算（平均値）
  LatLng _calculateCenter(List<LatLng> points) {
    final lat = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final lng = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
    return LatLng(lat, lng);
  }
}