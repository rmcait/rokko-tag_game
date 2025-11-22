import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../data/services/party_service.dart';
import '../../routes.dart';
import 'game_over_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ntp/ntp.dart'; // ★追加
import 'package:turf/turf.dart' as turf;
class RoomGamePageArgs {
  final PartyLobbyData lobby;
  final String currentUserId;
  final String gameId;

  const RoomGamePageArgs({
    required this.lobby,
    required this.currentUserId,
    required this.gameId,
  });
}

class RoomGamePage extends StatefulWidget {
  final RoomGamePageArgs args;

  const RoomGamePage({super.key, required this.args});

  @override
  State<RoomGamePage> createState() => _RoomGamePageState();
}
class _PlayerInfo {
  final String id;
  final String name;
  final LatLng position;
  final String role;  // 'TAGGER' or 'RUNNER' or 'PENDING'
  final bool isMe;
  final bool inside;
  final bool caught;

  const _PlayerInfo({
    required this.id,
    required this.name,
    required this.position,
    required this.role,
    required this.isMe,
    required this.inside,
    required this.caught,
  });
}
class _RoomGamePageState extends State<RoomGamePage> {
  final PartyService _partyService = PartyService();

  StreamSubscription<Position>? _posSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _playersSub;

  String? _myRoleCode;          // 'TAGGER' / 'RUNNER' / 'PENDING'
  GeoPoint? _myLastGeo;
  bool _alreadyNotifiedCaught = false;

  bool _canCatch = false;
  final List<DocumentReference<Map<String, dynamic>>> _nearRunnerRefs = [];

  final List<_PlayerInfo> _players = [];
  

  late PartyMemberRole _role;
  late _RolePalette _palette;
  PartyLobbyData? _latestLobby;

  Timer? _ticker;
  GameSessionData? _gameSession;
  StreamSubscription<GameSessionData?>? _gameSessionSub;
  int _countdown = 0;
  bool _showGo = false;

  int _capturedCount = 0;
  final List<String> _items = [];
  late int _remainingSeconds;
  String? _initErrorMessage;

  GoogleMapController? _mapController;
  LatLng? _currentLatLng;
  bool _isLocating = true;
  String? _locationError;
  final Set<Marker> _markers = {};
  Set<Polygon> _fieldPolygons = {};
  List<_PlayerInfo> get _otherPlayers =>
        _players.where((p) => !p.isMe).toList();
  List<LatLng> _fieldPoints = [];
  bool _outsideNotified = false;
  int _ntpOffset = 0;
  @override
  void initState() {
    super.initState();
    _latestLobby = widget.args.lobby;
    _initializeAsync();
    try {
      _role = _resolveRole();
    } catch (e, s) {
      _initErrorMessage = 'プレイヤー情報を取得できませんでした。';
      _role = PartyMemberRole.pending;
      debugPrint('Failed to resolve role for user ${widget.args.currentUserId}: $e\n$s');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showCriticalErrorAndExit(_initErrorMessage!);
      });
    }
    _palette = _RolePalette.of(_role);
    _remainingSeconds = widget.args.lobby.durationMinutes * 60;
    // 残りの初期化は非同期メソッドに分離
  }

  Future<void> _initializeAsync() async {
    await _syncTime();
    if (_initErrorMessage != null || !mounted) return;
    _startTicker();
    _listenToGameSession();
    _loadCurrentLocation();
    _loadFieldPolygon();
    _startLocationWatch(); // ★ 追加：継続的な位置送信
    _startPlayersWatch();
    _refreshLobbyRole();
  }
  // ★追加: NTP同期メソッド
  Future<void> _syncTime() async {
    try {
      // インターネット経由で正確な時刻との差分を取得
      _ntpOffset = await NTP.getNtpOffset(localTime: DateTime.now());
    } catch (e) {
      debugPrint('NTP Sync failed: $e');
      // 失敗してもエラーにはせず、端末時間(_ntpOffset=0)で動かす
    }
  }

  void _startLocationWatch() {
  _posSub = Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ),
  ).listen((pos) async {
    final current = LatLng(pos.latitude, pos.longitude);

      setState(() {
        _currentLatLng = current;
      });

    // Firestore に自分の位置を書き込む
    final gameId = widget.args.lobby.gameId;
    if (gameId == null || gameId.isEmpty) return;
    final playerId = widget.args.currentUserId;

    debugPrint('[LOC] send $current to game=$gameId player=$playerId');

    await FirebaseFirestore.instance
        .collection('gameSessions')
        .doc(gameId)
        .collection('players')
        .doc(playerId)
        .set(
      {
        'lastLocation': GeoPoint(pos.latitude, pos.longitude),
        'inside': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

      _checkFieldBoundary(current);
    });
  }
    void _startPlayersWatch() {
    final gameId = widget.args.lobby.gameId;
    if (gameId == null || gameId.isEmpty) return;

    _playersSub = FirebaseFirestore.instance
        .collection('gameSessions')
        .doc(gameId)
        .collection('players')
        .snapshots()
        .listen((snapshot) async {
      debugPrint('[PLAYERS] gameId=$gameId docs=${snapshot.docs.length}');
      final players = <_PlayerInfo>[];

      GeoPoint? myGeo;
      String? myRole;
      bool myCaught = false;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final geo = data['lastLocation'] as GeoPoint?;
        if (geo == null) continue;

        final role = data['role'] as String? ?? 'PENDING';
        final inside = (data['inside'] as bool?) ?? false;
        final caught = (data['caught'] as bool?) ?? false;
        final isMe = doc.id == widget.args.currentUserId;
        final name =
            data['displayName'] as String? ?? 'Player ${doc.id.substring(0, 4)}';

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
            role: role,
            isMe: isMe,
            inside: inside,
            caught: caught,
          ),
        );
      }

      final captured = players.where((p) => p.caught).length;

    // ★ 逃走側が捕まったときの通知（1回だけ）
    if (myRole == 'RUNNER' && myCaught && !_alreadyNotifiedCaught) {
      _alreadyNotifiedCaught = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('捕まってしまいました…！')),
        );
        //Game Over時の画面遷移
        Future.microtask(() {
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed(
            AppRoutes.gameOver, // ←あなたのルート名に合わせて変更
            arguments: GameOverPageArgs(
              lobby: _latestLobby ?? widget.args.lobby,
              gameId: widget.args.gameId,
              currentUserId: widget.args.currentUserId,
            ),
          );
        });
      }
    }

    if (!mounted) return;

    // 状態更新
    setState(() {
      _players
        ..clear()
        ..addAll(players);
      _myLastGeo = myGeo;
      _myRoleCode = myRole;
      _capturedCount = captured;
    });

    // マーカー描画を更新
    _updateMarkersFromPlayers(players);

    // ★ 鬼のときだけ、近くに捕まえられる相手がいるか判定
    _updateCatchAvailability(
      myGeo: myGeo,
      myRole: myRole,
      snapshot: snapshot,
    );
    });
  }
    void _updateCatchAvailability({
  required GeoPoint? myGeo,
  required String? myRole,
  required QuerySnapshot<Map<String, dynamic>> snapshot,
}) {
  // Firestore側のロールが PENDING でも、
  // ロビー情報 (_role) が鬼なら TAGGER とみなす
  String effectiveRole;

  if (myRole == null || myRole == 'PENDING') {
    if (_role == PartyMemberRole.tagger) {
      effectiveRole = 'TAGGER';
    } else if (_role == PartyMemberRole.runner) {
      effectiveRole = 'RUNNER';
    } else {
      effectiveRole = 'PENDING';
    }
  } else {
    effectiveRole = myRole;
  }

  // デバッグ用ログ
  debugPrint(
      '[CATCH] myRoleFromPlayers=$myRole lobbyRole=$_role effectiveRole=$effectiveRole myGeo=$myGeo');

  // 自分の位置 or 役割が不明、もしくは鬼じゃない → キャッチ不可
  if (myGeo == null || effectiveRole != 'TAGGER') {
    if (mounted) {
      setState(() {
        _canCatch = false;
        _nearRunnerRefs.clear();
      });
    }

    debugPrint(
        '[CATCH] not tagger or no position: effectiveRole=$effectiveRole myGeo=$myGeo');
    return;
  }

  const touchThresholdMeters = 20.0; // ★ 距離はここで調整（今は8m）

  final nearRunners = <DocumentReference<Map<String, dynamic>>>[];

  for (final doc in snapshot.docs) {
    if (doc.id == widget.args.currentUserId) continue;

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

    debugPrint(
        '[CATCH] candidate=${doc.id} role=$role distance=$distance caught=$caught');

    if (distance <= touchThresholdMeters) {
      nearRunners.add(doc.reference);
    }
  }

  if (mounted) {
    setState(() {
      _canCatch = nearRunners.isNotEmpty;
      _nearRunnerRefs
        ..clear()
        ..addAll(nearRunners);
    });
  }
  debugPrint(
      '[CATCH] result canCatch=$_canCatch nearRunners=${nearRunners.length}');
}

    Future<void> _onCatchPressed() async {
    // 念のためチェック
    if (_myRoleCode != 'TAGGER') return;

    if (_nearRunnerRefs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('近くに捕まえられる相手がいません')),
        );
      }
      return;
    }

    // 近くにいる RUNNER 全員を捕まえたことにする
    for (final ref in _nearRunnerRefs) {
      await ref.update({
        'caught': true,
        'caughtAt': FieldValue.serverTimestamp(),
        'caughtBy': widget.args.currentUserId,
      });
    }

    if (mounted) {
      setState(() {
        _canCatch = false;
        _nearRunnerRefs.clear();
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('捕まえました！')),
      );
    }
  }

  void _updateMarkersFromPlayers(List<_PlayerInfo> players) {
    final newMarkers = <Marker>{};

    for (final p in players) {
      // 色をロールで分ける
      if (p.isMe) continue;

      double hue;
      if (p.role == 'TAGGER') {
        hue = BitmapDescriptor.hueRed;
      } else {
        hue = BitmapDescriptor.hueOrange;
      }

      newMarkers.add(
        Marker(
          markerId: MarkerId(p.id),
          position: p.position,
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title: p.isMe ? 'あなた' : p.name,
            snippet: p.caught ? '捕まった！' : '',
          ),
        ),
      );
    }

    setState(() {
      _markers
        ..clear()
        ..addAll(newMarkers);
    });
  }
// Future<void> _handleTagLogic({
//   required GeoPoint? myGeo,
//   required String? myRole,
//   required bool myCaught,
//   required QuerySnapshot<Map<String, dynamic>> snapshot,
// }) async {
//   if (myGeo == null || myRole == null) return;

//   // 逃走側が捕まったときの通知（1回だけ）
//   if (myRole == 'RUNNER' && myCaught && !_alreadyNotifiedCaught) {
//     _alreadyNotifiedCaught = true;
//     if (mounted) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('捕まってしまいました…！')),
//       );
//     }
//   }

//   // 鬼以外はここで終了
//   if (myRole != 'TAGGER') return;

//   const touchThresholdMeters = 8.0;

//   for (final doc in snapshot.docs) {
//     if (doc.id == widget.args.currentUserId) continue;

//     final data = doc.data();
//     final role = data['role'] as String?;
//     if (role != 'RUNNER') continue;

//     final caught = (data['caught'] as bool?) ?? false;
//     if (caught) continue;

//     final geo = data['lastLocation'] as GeoPoint?;
//     if (geo == null) continue;

//     final distance = Geolocator.distanceBetween(
//       myGeo.latitude,
//       myGeo.longitude,
//       geo.latitude,
//       geo.longitude,
//     );

//     if (distance <= touchThresholdMeters) {
//       // ★ 捕まえた！
//       await doc.reference.update({
//         'caught': true,
//         'caughtAt': FieldValue.serverTimestamp(),
//         'caughtBy': widget.args.currentUserId,
//       });
//     }
//   }
// }
   // ★ プレイヤー名の吹き出しを作る
  Future<List<Widget>> _buildPlayerBubbles() async {
    if (_mapController == null) return [];

    final bubbles = <Widget>[];

    for (final p in _otherPlayers) {
      // マーカーの位置をスクリーン座標に変換
      final screenPoint =
          await _mapController!.getScreenCoordinate(p.position);

      bubbles.add(
        Positioned(
          left: screenPoint.x.toDouble() - 30, // 少し中央寄せ
          top: screenPoint.y.toDouble() - 60,  // マーカーの上に出したいので上にずらす
          child: _PlayerBubble(name: p.name),
        ),
      );
    }

    return bubbles;
  }

  void _checkFieldBoundary(LatLng point) {
    if (_fieldPoints.length < 3) return;

    final ring = _fieldPoints
        .map((p) => turf.Position(p.longitude, p.latitude))
        .toList();

    // クローズリングで判定の精度を上げる
    if (ring.isNotEmpty &&
        (ring.first.lng != ring.last.lng || ring.first.lat != ring.last.lat)) {
      ring.add(ring.first);
    }

    final polygon = turf.Polygon(coordinates: [ring]);
    final pt = turf.Position(point.longitude, point.latitude);
    final inside = turf.booleanPointInPolygon(pt, polygon);

    if (!inside && !_outsideNotified) {
      _outsideNotified = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在地はエリア外です')),
      );
    } else if (inside) {
      // エリア内に戻ったら通知状態をリセット
      _outsideNotified = false;
    }
  }
  // ★追加: 補正済みの「今」を取得するゲッター
  DateTime get _now => DateTime.now().add(Duration(milliseconds: _ntpOffset));
  @override
  void dispose() {
    _ticker?.cancel();
    _gameSessionSub?.cancel();
    _mapController?.dispose();

    _posSub?.cancel();
    _playersSub?.cancel();

    super.dispose();
  }

  PartyMemberRole _resolveRole() {
    final members = _latestLobby?.allMembers ?? widget.args.lobby.allMembers;
    final me = members.firstWhere(
      (m) => m.userId == widget.args.currentUserId,
    );
    return me.role;

    
  }

  Future<void> _refreshLobbyRole() async {
    try {
      final refreshed =
          await _partyService.fetchPartyLobbyById(widget.args.lobby.partyId);
      if (!mounted || refreshed == null) return;
      final members = refreshed.allMembers;
      final me = members.where((m) => m.userId == widget.args.currentUserId).toList();
      if (me.isEmpty) return;
      final newRole = me.first.role;
      setState(() {
        _latestLobby = refreshed;
        if (newRole != _role) {
          _role = newRole;
          _palette = _RolePalette.of(_role);
        }
      });
    } catch (e, s) {
      debugPrint('Failed to refresh lobby for role: $e\n$s');
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateTimeFromSession(),
    );
  }

  void _listenToGameSession() {
    final gameId = widget.args.lobby.gameId;
    if (gameId == null) {
      debugPrint('No gameId on lobby; cannot sync time.');
      return;
    }
    _gameSessionSub = _partyService.watchGameSession(gameId).listen((session) {
      if (!mounted) return;
      setState(() => _gameSession = session);
      _updateTimeFromSession();
    });
  }

  // ★修正: 時間計算ロジック
  void _updateTimeFromSession() {
    final session = _gameSession;
    if (session == null) return;

    // ★修正: 補正済みの現在時刻を使う
    final now = _now;

    var remaining = _remainingSeconds;
    final startAt = session.startAt;

    if (startAt != null) {
      // ゲーム終了予定時刻の計算
      final computedEnd = session.endAt ?? 
          startAt.add(Duration(minutes: session.durationMinutes));
      
      remaining = computedEnd.difference(now).inSeconds;
      final maxSeconds = session.durationMinutes * 60;
      remaining = remaining.clamp(0, maxSeconds);
    }

    // カウントダウン（鬼の待機時間）の計算
    var countdown = 0;
    var showGo = _showGo;

    // ★修正: freezeUntil はDBの値を使わず、startAt + 30秒 で計算する
    // これによりホストの時計ズレの影響を排除できる
    if (startAt != null) {
      final freezeUntilCorrected = startAt.add(const Duration(seconds: 3));
      final diff = freezeUntilCorrected.difference(now).inSeconds;

      if (diff > 0) {
        countdown = diff;
        showGo = false;
      } else {
        // 0になった瞬間の "GO!" 表示制御
        if (_countdown > 0 && diff <= 0) {
          showGo = true;
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              setState(() => _showGo = false);
            }
          });
        }
        countdown = 0;
      }
    }

    if (!mounted) return;
    setState(() {
      _remainingSeconds = remaining;
      _countdown = countdown;
      _showGo = showGo;
    });
  }
  Future<void> _loadCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError = '位置情報サービスが無効です';
          _isLocating = false;
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
          _locationError = '位置情報の権限がありません';
          _isLocating = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final latLng = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentLatLng = latLng;
        _isLocating = false;
        _locationError = null;
        // _markers
        //   ..clear()
        //   ..add(
        //     Marker(
        //       markerId: const MarkerId('me'),
        //       position: latLng,
        //       icon: BitmapDescriptor.defaultMarkerWithHue(
        //         BitmapDescriptor.hueAzure,
        //       ),
        //     ),
        //   );
      });

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, 17),
      );
      _checkFieldBoundary(latLng);
    } catch (e) {
      setState(() {
        _locationError = '位置情報取得に失敗しました: $e';
        _isLocating = false;
      });
    }
  }

  Future<void> _loadFieldPolygon() async {
    try {
      final polygon =
          await _partyService.fetchPartyPolygon(widget.args.lobby.partyId);
      if (!mounted || polygon == null || polygon.isEmpty) return;
      setState(() {
        _fieldPoints = polygon;
        _fieldPolygons = {
          Polygon(
            polygonId: const PolygonId('field'),
            points: polygon,
            fillColor: _palette.accent.withOpacity(0.12),
            strokeColor: _palette.accent,
            strokeWidth: 2,
          ),
        };
      });
    } catch (e, s) {
      debugPrint('Failed to load field polygon: $e\n$s');
    }
  }

  void _goHome() {
    final gameId = widget.args.lobby.gameId;
    if (gameId != null && gameId.isNotEmpty) {
      _partyService.updateGameStatus(
        gameId: gameId,
        status: 'ABORTED',
        partyId: widget.args.lobby.partyId,
      );
    }
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  Future<void> _showCriticalErrorAndExit(String message) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('エラー'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).maybePop();
            },
            child: const Text('戻る'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initErrorMessage != null) {
      return const SizedBox.shrink();
    }

    final totalPlayers = widget.args.lobby.memberCount;
    final remainingPlayers =
        (totalPlayers - _capturedCount).clamp(0, totalPlayers).toInt();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('ゲーム中'),
        backgroundColor: _palette.accent,
        automaticallyImplyLeading: true,
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: _goHome,
        ),
      ),
      body: WillPopScope(
        onWillPop: () async {
          final shouldExit =
              await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('ゲームを中断しますか？'),
                      content: const Text('ロビー画面に戻ります。'),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(context).pop(false),
                          child: const Text('キャンセル'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(context).pop(true),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
          return shouldExit;
        },
            child: Stack(
              children: [
                // ① マップ本体
                Positioned.fill(
                  child: _MapLayer(
                    currentLatLng: _currentLatLng,
                    markers: _markers,
                    polygons: _fieldPolygons,
                    isLocating: _isLocating,
                    error: _locationError,
                    onMapCreated: (controller) => _mapController = controller,
                    accent: _palette.accent,
                  ),
                ),

                // ② プレイヤー名の吹き出しレイヤー
                Positioned.fill(
                  child: IgnorePointer(
                    child: FutureBuilder<List<Widget>>(
                      future: _buildPlayerBubbles(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const SizedBox.shrink();
                        }
                        return Stack(children: snapshot.data!);
                      },
                    ),
                  ),
                ),

                // ③ ズームボタン（右上気味に配置して埋もれないようにする）
                Positioned(
                  right: 16,
                  top: 120,
                  child: Column(
                    children: [
                      FloatingActionButton(
                        heroTag: 'zoomIn',
                        mini: true,
                        backgroundColor: Colors.white,
                        onPressed: () {
                          _mapController?.animateCamera(
                            CameraUpdate.zoomIn(),
                          );
                        },
                        child: const Icon(Icons.add, color: Colors.black),
                      ),
                      const SizedBox(height: 12),
                      FloatingActionButton(
                        heroTag: 'zoomOut',
                        mini: true,
                        backgroundColor: Colors.white,
                        onPressed: () {
                          _mapController?.animateCamera(
                            CameraUpdate.zoomOut(),
                          );
                        },
                        child: const Icon(Icons.remove, color: Colors.black),
                      ),
                    ],
                  ),
                ),

                // ④ 既存のUI（タイマーやステータス）
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TimeAndRoleHeader(
                          palette: _palette,
                          remainingSeconds: _remainingSeconds,
                        ),
                        const Spacer(),
                        _CountdownOverlay(
                          countdown: _countdown,
                          showGo: _showGo,
                          accent: _palette.accent,
                        ),
                        const Spacer(),
                        _StatsBar(
                          accent: _palette.accent,
                          capturedCount: _capturedCount,
                          remainingPlayers: remainingPlayers,
                          items: _items,
                        ),
                        if (_role == PartyMemberRole.tagger) ...[
                          const SizedBox(height: 12),
                          _CatchButton(
                            accent: _palette.accent,
                            enabled: _canCatch,     // ★ 近くに相手がいるときだけ有効
                            onPressed: _onCatchPressed,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
      ),
    );
  }
}

class _CatchButton extends StatelessWidget {
  final Color accent;
  final VoidCallback onPressed;
  final bool enabled;

  const _CatchButton({
    required this.accent,
    required this.onPressed,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        // enabled = false のときは null にして無効化
        onPressed: enabled ? onPressed : null,
        child: const Text(
          'Catch',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
class _PlayerBubble extends StatelessWidget {
  final String name;

  const _PlayerBubble({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
class _MapLayer extends StatelessWidget {
  final LatLng? currentLatLng;
  final Set<Marker> markers;
  final Set<Polygon> polygons;
  final bool isLocating;
  final String? error;
  final void Function(GoogleMapController controller) onMapCreated;
  final Color accent;

  const _MapLayer({
    required this.currentLatLng,
    required this.markers,
    required this.polygons,
    required this.isLocating,
    required this.error,
    required this.onMapCreated,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final defaultCamera = CameraPosition(
      target: currentLatLng ?? const LatLng(35.0, 135.0),
      zoom: 15,
    );

    return Stack(
      children: [
        GoogleMap(
          onMapCreated: onMapCreated,
          initialCameraPosition: defaultCamera,
          markers: markers,
          polygons: polygons,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
        ),
        if (isLocating)
          Positioned.fill(
            child: Container(
              color: Colors.white.withOpacity(0.6),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        if (error != null && !isLocating)
          Positioned(
            top: 24,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.error, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CountdownOverlay extends StatelessWidget {
  final int countdown;
  final bool showGo;
  final Color accent;

  const _CountdownOverlay({
    required this.countdown,
    required this.showGo,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (countdown <= 0 && !showGo) return const SizedBox.shrink();
    final text = showGo ? 'GO!' : '$countdown';
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Container(
          key: ValueKey<String>(text),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            shape: BoxShape.circle,
            border: Border.all(color: accent, width: 4),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: showGo ? 64 : 72,
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final Color accent;
  final int capturedCount;
  final int remainingPlayers;
  final List<String> items;

  const _StatsBar({
    required this.accent,
    required this.capturedCount,
    required this.remainingPlayers,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(2).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.backpack, size: 18),
              const SizedBox(width: 8),
              const Text(
                '所持アイテム (最大2個)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                '${visibleItems.length}/2',
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (visibleItems.isEmpty)
            const Text(
              'まだアイテムはありません',
              style: TextStyle(color: Colors.black54),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: visibleItems
                  .map(
                    (item) => Chip(
                      label: Text(item),
                      backgroundColor: accent.withOpacity(0.12),
                      labelStyle: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                  .toList(),
            ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatPill(
                icon: Icons.lock_person,
                label: '確保',
                value: capturedCount,
                accent: accent,
              ),
              _StatPill(
                icon: Icons.group,
                label: '残り',
                value: remainingPlayers,
                accent: accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color accent;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: accent),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TimeAndRoleHeader extends StatelessWidget {
  final _RolePalette palette;
  final int remainingSeconds;

  const _TimeAndRoleHeader({
    required this.palette,
    required this.remainingSeconds,
  });

  String _format(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.timer, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '残り時間',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  _format(remainingSeconds),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        _RoleBadge(palette: palette),
      ],
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final _RolePalette palette;

  const _RoleBadge({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(palette.icon, color: palette.accent),
          const SizedBox(width: 8),
          Text(
            palette.label,
            style: TextStyle(
              color: palette.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _RolePalette {
  final Color accent;
  final Color background;
  final IconData icon;
  final String label;

  const _RolePalette({
    required this.accent,
    required this.background,
    required this.icon,
    required this.label,
  });

  static _RolePalette of(PartyMemberRole role) {
    switch (role) {
      case PartyMemberRole.tagger:
        return const _RolePalette(
          accent: Color(0xFFE57373),
          background: Color(0xFFFFEBEE),
          icon: Icons.local_fire_department,
          label: '鬼チーム',
        );
      case PartyMemberRole.runner:
        return const _RolePalette(
          accent: Color(0xFF42A5F5),
          background: Color(0xFFE3F2FD),
          icon: Icons.directions_run,
          label: '逃走チーム',
        );
      case PartyMemberRole.pending:
      default:
        return const _RolePalette(
          accent: Colors.grey,
          background: Color(0xFFE0E0E0),
          icon: Icons.hourglass_bottom,
          label: '待機中',
        );
    }
  }
}
