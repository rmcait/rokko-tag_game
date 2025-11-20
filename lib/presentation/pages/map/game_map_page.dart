// lib/presentation/pages/map/game_map_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tag_game/data/services/game_service.dart';

class GameMapPage extends StatefulWidget {
  final String gameId;
  final String playerId;

  const GameMapPage({
    super.key,
    required this.gameId,
    required this.playerId,
  });

  @override
  State<GameMapPage> createState() => _GameMapPageState();
}

class _GameMapPageState extends State<GameMapPage> {
  GoogleMapController? _mapController;
  LatLng? _currentLatLng;
  bool _isLoading = true;
  String? _errorMessage;

  StreamSubscription<Position>? _posSub;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[GameMapPage] initState gameId=${widget.gameId}, playerId=${widget.playerId}',
    );
    _loadCurrentLocation().then((_) {
      _startLocationWatch();
    });
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _errorMessage = '位置情報サービスが無効です。端末の設定を確認してください。';
          _isLoading = false;
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _errorMessage = '位置情報の権限が許可されていません。';
          _isLoading = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLatLng = LatLng(position.latitude, position.longitude);
        _isLoading = false;
        _errorMessage = null;
      });

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_currentLatLng!, 16),
      );
    } catch (e) {
      setState(() {
        _errorMessage = '位置情報取得に失敗しました: $e';
        _isLoading = false;
      });
    }
  }

  void _startLocationWatch() {
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // 5m ごとに更新
      ),
    ).listen((pos) async {
      final current = LatLng(pos.latitude, pos.longitude);

      debugPrint(
        '[GameMapPage] position update lat=${pos.latitude}, lng=${pos.longitude}',
      );

      // カメラを現在地に少し追従（邪魔なら消してOK）
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(current),
      );

      // ひとまず inside=false 固定（フィールド判定は後でつなぐ）
      const inside = false;

      try {
        await GameService().updatePlayerLocation(
          gameId: widget.gameId,
          playerId: widget.playerId,
          lat: pos.latitude,
          lng: pos.longitude,
          inside: inside,
        );
        debugPrint('[GameMapPage] updatePlayerLocation done');
      } catch (e) {
        debugPrint('[GameMapPage] updatePlayerLocation error: $e');
      }
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_currentLatLng != null) {
      controller.moveCamera(
        CameraUpdate.newLatLngZoom(_currentLatLng!, 16),
      );
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_errorMessage != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _loadCurrentLocation();
                },
                child: const Text('再試行'),
              ),
            ],
          ),
        ),
      );
    } else {
      body = GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(
          target: _currentLatLng ?? const LatLng(35.681236, 139.767125),
          zoom: 16,
        ),
        myLocationEnabled: true,       // 青丸
        myLocationButtonEnabled: true, // 右下の現在地ボタン
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ゲーム中マップ（テスト）'),
      ),
      body: body,
    );
  }
}