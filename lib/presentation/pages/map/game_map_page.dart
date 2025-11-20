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
  String? _myRoleCode;            // 'TAGGER' / 'RUNNER' / 'PENDING'
  GeoPoint? _myLastGeo;           // 自分の位置（Firestore上）
  bool _alreadyNotifiedCaught = false;
  
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
      .listen((snapshot) async {
    debugPrint(
        '[GameMapPage] players snapshot: ${snapshot.docs.length} docs');

    final markers = <Marker>{};

    GeoPoint? myGeo;
    String? myRole;
    bool myCaught = false;

    // まずは全員分を読みつつ、自分の情報も拾う
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final geo = data['lastLocation'] as GeoPoint?;
      if (geo == null) continue;

      final role = data['role'] as String?; // TAGGER / RUNNER / PENDING
      final caught = (data['caught'] as bool?) ?? false;
      final isMe = doc.id == widget.playerId;

      if (isMe) {
        myGeo = geo;
        myRole = role;
        myCaught = caught;
        continue; // ★ 自分の上のマーカーは出さない
      }

      // 他プレイヤーのマーカー色を決める
      final hue = caught
          ? BitmapDescriptor.hueRose // 捕まってたらピンクとか
          : BitmapDescriptor.hueOrange;

      markers.add(
        Marker(
          markerId: MarkerId('player_${doc.id}'),
          position: LatLng(geo.latitude, geo.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title: 'Player ${doc.id.substring(0, 4)}',
            snippet: 'role: $role, caught: $caught',
          ),
        ),
      );
    }

    setState(() {
      _playerMarkers = markers;
      _myRoleCode = myRole;
      _myLastGeo = myGeo;
    });

    // ここからタッチ判定ロジック

    // 自分の位置 or ロールがまだ無いなら何もしない
    if (myGeo == null || myRole == null) {
      return;
    }

    // ① 自分が RUNNER で、捕まったら「捕まったよ」通知したい場合（オプション）
    if (myRole == 'RUNNER' && myCaught && !_alreadyNotifiedCaught) {
      _alreadyNotifiedCaught = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('捕まってしまいました…！')),
        );
      }
    }

    // ② 自分が TAGGER なら、距離を見てタッチ判定
    if (myRole != 'TAGGER') {
      return;
    }

    const double touchThresholdMeters = 8.0; // ★ タッチ判定距離（メートル）

    for (final doc in snapshot.docs) {
      if (doc.id == widget.playerId) continue; // 自分はスキップ

      final data = doc.data();
      final role = data['role'] as String?;
      if (role != 'RUNNER') continue; // 逃走者だけ見る

      final caught = (data['caught'] as bool?) ?? false;
      if (caught) continue; // すでに捕まってる人はスキップ

      final geo = data['lastLocation'] as GeoPoint?;
      if (geo == null) continue;

      // 距離計算
      final distance = Geolocator.distanceBetween(
        myGeo.latitude,
        myGeo.longitude,
        geo.latitude,
        geo.longitude,
      );

      if (distance <= touchThresholdMeters) {
        debugPrint(
            '[GameMapPage] TAGGED player ${doc.id} (distance=${distance.toStringAsFixed(1)}m)');

        // Firestore 上でそのRUNNERを捕まった状態にする
        await FirebaseFirestore.instance
            .collection('gameSessions')
            .doc(widget.gameId)
            .collection('players')
            .doc(doc.id)
            .update({
          'caught': true,
          'caughtAt': FieldValue.serverTimestamp(),
          'caughtBy': widget.playerId,
        });
      }
    }
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