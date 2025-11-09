import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _controller;
  LatLng _cameraTarget = const LatLng(35.681236, 139.767125); // 初期: 東京駅
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // 位置サービス無効時の簡易ハンドリング
        setState(() => _loading = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _loading = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _cameraTarget = latLng;
        _loading = false;
      });

      // カメラを現在地へ移動
      _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, 16),
      );
    } catch (e) {
      // 必要ならトーストやダイアログ
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('現在地マップ')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
              onMapCreated: (c) => _controller = c,
              initialCameraPosition: CameraPosition(
                target: _cameraTarget,
                zoom: 14,
              ),
              myLocationEnabled: true,        // 青い現在地ドット
              myLocationButtonEnabled: true,  // 右上の現在地ボタン
            ),
    );
  }
}