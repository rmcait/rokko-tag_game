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
  LatLng? _currentLatLng;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initCurrentLocation();
  }

  /// 現在地を取得して初期位置に設定
  Future<void> _initCurrentLocation() async {
    try {
      // 位置情報サービスが有効か確認
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('位置情報サービスが無効です')),
        );
        return;
      }

      // 権限確認・リクエスト
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('位置情報が永続的に拒否されています。設定から許可してください。')),
        );
        return;
      }

      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('位置情報の許可が必要です')),
        );
        return;
      }

      // 現在地取得
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final latLng = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentLatLng = latLng;
        _loading = false;
      });

      // GoogleMapControllerがすでに作られていたら移動
      _controller?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
    } catch (e) {
      debugPrint('位置情報取得エラー: $e');
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
              onMapCreated: (controller) {
                _controller = controller;
                // すぐにカメラを現在地に移動
                if (_currentLatLng != null) {
                  _controller!.animateCamera(
                    CameraUpdate.newLatLngZoom(_currentLatLng!, 16),
                  );
                }
              },
              initialCameraPosition: CameraPosition(
                target: _currentLatLng ?? const LatLng(35.681236, 139.767125),
                zoom: 16,
              ),
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
            ),
    );
  }
}