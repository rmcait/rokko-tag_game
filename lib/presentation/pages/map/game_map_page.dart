// lib/presentation/pages/map/game_map_page.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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

  // 位置情報ストリーム
  StreamSubscription<Position>? _posSub;

  // Firestore の players サブコレクション監視
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _playersSub;

  /// Firestore 上の全プレイヤーをマーカー表示
  Set<Marker> _playerMarkers = {};

  @override
  void initState() {
    super.initState();
    debugPrint(
        '[GameMapPage] initState gameId=${widget.gameId}, playerId=${widget.playerId}');

    _loadCurrentLocation().then((_) {
      _startLocationWatch();
      _startPlayersWatch();
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _playersSub?.cancel();
    _mapController?.dispose();
    super.dispose();
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

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_currentLatLng != null) {
      controller.moveCamera(
        CameraUpdate.newLatLngZoom(_currentLatLng!, 16),
      );
    }
  }

  /// 自分の端末位置を監視して Firestore に送る
  void _startLocationWatch() {
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) async {
      final current = LatLng(pos.latitude, pos.longitude);
      debugPrint(
          '[GameMapPage] position update lat=${pos.latitude}, lng=${pos.longitude}');

      setState(() {
        _currentLatLng = current;
      });

      // Firestore へ自分の位置を同期
      await GameService().updatePlayerLocation(
        gameId: widget.gameId,
        playerId: widget.playerId,
        lat: pos.latitude,
        lng: pos.longitude,
        // inside はとりあえず false（まだエリア判定をここではやらない）
        inside: false,
      );

      debugPrint('[GameMapPage] updatePlayerLocation done');
    });
  }

  /// Firestore の gameSessions/{gameId}/players を監視して
  /// すべてのプレイヤー位置をマーカーに反映
  void _startPlayersWatch() {
    _playersSub = FirebaseFirestore.instance
        .collection('gameSessions')
        .doc(widget.gameId)
        .collection('players')
        .snapshots()
        .listen((snapshot) {
      debugPrint(
          '[GameMapPage] players snapshot: ${snapshot.docs.length} docs');

      final markers = <Marker>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final geo = data['lastLocation'] as GeoPoint?;
        if (geo == null) continue;

        final inside = (data['inside'] as bool?) ?? false;
        final isMe = doc.id == widget.playerId;

        final hue = isMe
            ? BitmapDescriptor.hueAzure // 自分は青
            : (inside
                ? BitmapDescriptor.hueGreen // エリア内の他人は緑
                : BitmapDescriptor.hueOrange); // エリア外の他人はオレンジ

        markers.add(
          Marker(
            markerId: MarkerId('player_${doc.id}'),
            position: LatLng(geo.latitude, geo.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(hue),
            infoWindow: InfoWindow(
              title: isMe ? 'あなた' : 'Player ${doc.id.substring(0, 4)}',
              snippet: 'inside: $inside',
            ),
          ),
        );
      }

      setState(() {
        _playerMarkers = markers;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('ゲームマップ')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('ゲームマップ')),
        body: Center(
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
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ゲームマップ'),
      ),
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(
          target: _currentLatLng ?? const LatLng(35.681236, 139.767125),
          zoom: 16,
        ),
        myLocationEnabled: true, // 青丸はこれで出す
        myLocationButtonEnabled: true,
        markers: _playerMarkers,
      ),
    );
  }
}