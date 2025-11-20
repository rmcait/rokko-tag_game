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

class _PlayerInfo {
  final String id;
  final String name;
  final LatLng position;
  final bool isMe;
  final bool inside;

  const _PlayerInfo({
    required this.id,
    required this.name,
    required this.position,
    required this.isMe,
    required this.inside,
  });
}

class _GameMapPageState extends State<GameMapPage> {
  GoogleMapController? _mapController;
  LatLng? _currentLatLng;

  bool _isLoading = true;
  String? _errorMessage;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _playersSub;

  /// プレイヤー情報（UI とタッチ判定用）
  List<_PlayerInfo> _players = [];

  /// プレイヤーIDごとの画面座標（マップ上の位置にバッジを重ねる用）
  Map<String, Offset> _playerScreenPositions = {};

  /// 自分の Firestore 上の状態
  String? _myRoleCode; // 'TAGGER' / 'RUNNER' / 'PENDING'
  GeoPoint? _myLastGeo; // 自分の位置（Firestore 上）
  bool _alreadyNotifiedCaught = false;

  /// アイテム用マーカー（今は空）
  final Set<Marker> _itemMarkers = {};

  /// カメラ移動時のオーバーレイ更新デバウンス
  Timer? _overlayUpdateDebounce;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[GameMapPage] initState gameId=${widget.gameId}, playerId=${widget.playerId}',
    );

    _loadCurrentLocation().then((_) {
      _startLocationWatch();
      _startPlayersWatch();
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _playersSub?.cancel();
    _overlayUpdateDebounce?.cancel();
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
    // マップ生成直後にも一度オーバーレイ更新しておく
    _updatePlayerOverlays();
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
        '[GameMapPage] position update lat=${pos.latitude}, lng=${pos.longitude}',
      );

      setState(() {
        _currentLatLng = current;
      });

      // Firestore へ自分の位置を同期
      await GameService().updatePlayerLocation(
        gameId: widget.gameId,
        playerId: widget.playerId,
        lat: pos.latitude,
        lng: pos.longitude,
        inside: false, // エリア判定は別で
      );

      debugPrint('[GameMapPage] updatePlayerLocation done');
    });
  }

  /// Firestore の gameSessions/{gameId}/players を監視して
  /// すべてのプレイヤー位置を UI / タッチ判定に反映
  void _startPlayersWatch() {
    _playersSub = FirebaseFirestore.instance
        .collection('gameSessions')
        .doc(widget.gameId)
        .collection('players')
        .snapshots()
        .listen((snapshot) async {
      debugPrint(
        '[GameMapPage] players snapshot: ${snapshot.docs.length} docs',
      );

      final players = <_PlayerInfo>[];

      GeoPoint? myGeo;
      String? myRole;
      bool myCaught = false;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final geo = data['lastLocation'] as GeoPoint?;
        if (geo == null) continue;

        final inside = (data['inside'] as bool?) ?? false;
        final role = data['role'] as String?;
        final caught = (data['caught'] as bool?) ?? false;
        final isMe = doc.id == widget.playerId;

        // Firestore に displayName / nickname があれば拾う
        final firestoreName = data['displayName'] as String? ??
            data['nickname'] as String?;
        final name = firestoreName ?? 'Player';

        if (isMe) {
          myGeo = geo;
          myRole = role;
          myCaught = caught;
        }

        players.add(
          _PlayerInfo(
            id: doc.id,
            name: name,
            position: LatLng(geo.latitude, geo.longitude),
            isMe: isMe,
            inside: inside,
          ),
        );
      }

      setState(() {
        _players = players;
        _myLastGeo = myGeo;
        _myRoleCode = myRole;
      });

      // マップ上バッジの位置を更新
      _updatePlayerOverlays();

      // --- ここからタッチ判定ロジック ---

      if (myGeo == null || myRole == null) {
        return;
      }

      // ① 自分が RUNNER で、捕まったら「捕まったよ」通知（1回だけ）
      if (myRole == 'RUNNER' && myCaught && !_alreadyNotifiedCaught) {
        _alreadyNotifiedCaught = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('捕まってしまいました…！')),
          );
        }
      }

      // ② 自分が TAGGER でなければタッチ判定しない
      if (myRole != 'TAGGER') {
        return;
      }

      const double touchThresholdMeters = 8.0; // タッチ判定距離

      for (final doc in snapshot.docs) {
        if (doc.id == widget.playerId) continue;

        final data = doc.data();
        final role = data['role'] as String?;
        if (role != 'RUNNER') continue;

        final caught = (data['caught'] as bool?) ?? false;
        if (caught) continue;

        final geo = data['lastLocation'] as GeoPoint?;
        if (geo == null) continue;

        final distance = Geolocator.distanceBetween(
          myGeo.latitude,
          myGeo.longitude,
          geo.latitude,
          geo.longitude,
        );

        if (distance <= touchThresholdMeters) {
          debugPrint(
            '[GameMapPage] TAGGED player ${doc.id} (distance=${distance.toStringAsFixed(1)}m)',
          );

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

  /// プレイヤー位置を画面座標に変換して、_playerScreenPositions を更新
  Future<void> _updatePlayerOverlays() async {
    if (_mapController == null) return;
    if (_players.isEmpty) return;

    final controller = _mapController!;
    final newPositions = <String, Offset>{};

    for (final p in _players) {
      final screen = await controller.getScreenCoordinate(p.position);
      newPositions[p.id] = Offset(
        screen.x.toDouble(),
        screen.y.toDouble(),
      );
    }

    if (!mounted) return;
    setState(() {
      _playerScreenPositions = newPositions;
    });
  }

  /// 画面上部にプレイヤー一覧（名前＋アイコン）を表示する HUD
  Widget _buildPlayersHud() {
    if (_players.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: _players.map((p) {
            final isMe = p.isMe;
            final color = isMe
                ? Colors.blueAccent
                : (p.inside ? Colors.green : Colors.orange);

            // HUD では自分だけ「あなた」、他は Player
            final displayLabel = isMe ? 'あなた' : 'Player';

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(p.position, 17),
                  );
                },
                child: Chip(
                  avatar: CircleAvatar(
                    backgroundColor: color,
                    child: Icon(
                      isMe ? Icons.person : Icons.accessibility_new,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                  label: Text(
                    displayLabel,
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.black.withOpacity(0.7),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// マップ上にプレイヤー位置へバッジを重ねるオーバーレイ
  List<Widget> _buildPlayerOverlays() {
    final widgets = <Widget>[];

    for (final p in _players) {
      final pos = _playerScreenPositions[p.id];
      if (pos == null) continue;

      // 自分の上には表示しない（青丸だけ）
      if (p.isMe) continue;

      final isMe = p.isMe;
      final color = isMe
          ? Colors.blueAccent
          : (p.inside ? Colors.green : Colors.orange);

      // ここも自分以外は "Player" 固定
      final displayLabel = isMe ? 'あなた' : 'Player';

      widgets.add(
        Positioned(
          left: pos.dx - 40,
          top: pos.dy - 40,
          child: _PlayerBadge(
            color: color,
            label: displayLabel,   // ← 修正ポイント
            isMe: isMe,
          ),
        ),
      );
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('ゲームマップ')),
        body: const Center(child: CircularProgressIndicator()),
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
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            onCameraMove: (_) {
              _overlayUpdateDebounce?.cancel();
              _overlayUpdateDebounce =
                  Timer(const Duration(milliseconds: 50), _updatePlayerOverlays);
            },
            initialCameraPosition: CameraPosition(
              target: _currentLatLng ?? const LatLng(35.681236, 139.767125),
              zoom: 16,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: _itemMarkers, // プレイヤーは表示せず、アイテム用のみ
          ),
          _buildPlayersHud(),
          ..._buildPlayerOverlays(),
        ],
      ),
    );
  }
}

/// マップ上に重ねる小さめのプレイヤーバッジ
class _PlayerBadge extends StatelessWidget {
  final Color color;
  final String label;
  final bool isMe;

  const _PlayerBadge({
    required this.color,
    required this.label,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 9,
              backgroundColor: color,
              child: Icon(
                isMe ? Icons.person : Icons.person_outline,
                size: 12,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}