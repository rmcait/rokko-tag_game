import 'dart:async';
import 'dart:math';
import 'package:vibration/vibration.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../data/services/party_service.dart';
import '../../routes.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';import 'game_over_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ntp/ntp.dart'; 
import 'package:flutter/foundation.dart'; // ★追加：kDebugMode でデバッグ時だけボタンを出す
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

class _GameItem {
  final String itemId;
  final String type;
  final String visibility;
  final String state;
  final double lat;
  final double lng;

  const _GameItem({
    required this.itemId,
    required this.type,
    required this.visibility,
    required this.state,
    required this.lat,
    required this.lng,
  });

  factory _GameItem.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return _GameItem(
      itemId: data['itemId'] as String? ?? doc.id,
      type: data['type'] as String? ?? 'UNKNOWN',
      visibility: data['visibility'] as String? ?? 'RUNNER',
      state: data['state'] as String? ?? 'AVAILABLE',
      lat: (data['lat'] as num?)?.toDouble() ?? 0,
      lng: (data['lng'] as num?)?.toDouble() ?? 0,
    );
  }
}

const Set<String> _runnerVisibleItemTypes = {
  'FREEZE_TAGGER',
  'SEE_TAGGER',
  'FAKE_LOCATION',
};

const Set<String> _taggerVisibleItemTypes = {
  'TRAP',
  'FAKE_LOCATION_TAGGER',
};

class _ItemStates {
  static const available = 'AVAILABLE';
  static const picked = 'PICKED';
  static const armed = 'ARMED';
  static const used = 'USED';
}

Set<String> _visibleItemTypesForRole(PartyMemberRole role) {
  switch (role) {
    case PartyMemberRole.tagger:
      return _taggerVisibleItemTypes;
    case PartyMemberRole.runner:
    case PartyMemberRole.pending:
      return _runnerVisibleItemTypes;
  }
}
class _RoomGamePageState extends State<RoomGamePage> {
  final PartyService _partyService = PartyService();

  StreamSubscription<Position>? _posSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _playersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _itemsSub;

  String? _myRoleCode;          // 'TAGGER' / 'RUNNER' / 'PENDING'
  GeoPoint? _myLastGeo;
  bool _alreadyNotifiedCaught = false;

  bool _canCatch = false;
  final List<DocumentReference<Map<String, dynamic>>> _nearRunnerRefs = [];

  final List<_PlayerInfo> _players = [];
  final List<_GameItem> _gameItems = [];
  final List<_GameItem> _armedTraps = [];
  bool _isPickingItem = false;
  bool _isUsingItem = false;
  bool _freezeReady = false;
  final Random _random = Random();
  double _taggerGauge = 0;
  LatLng? _lastGaugePoint;
  bool _isListeningAbilityActive = false;

  late PartyMemberRole _role;
  late _RolePalette _palette;
  PartyLobbyData? _latestLobby;

  Timer? _ticker;
  GameSessionData? _gameSession;
  StreamSubscription<GameSessionData?>? _gameSessionSub;
  int _countdown = 0;
  bool _showGo = false;

  int _capturedCount = 0;
  int _totalRunners = 0; 
  final List<String> _items = [];
  late int _remainingSeconds;
  String? _initErrorMessage;

  GoogleMapController? _mapController;
  LatLng? _currentLatLng;
  bool _isLocating = true;
  String? _locationError;
  final Set<Marker> _markers = {};
  final Set<Marker> _playerMarkers = {};
  final Set<Marker> _itemMarkers = {};
  final Set<Marker> _effectMarkers = {};
  Timer? _revealTimer;
  GeoPoint? _lastTaggerGeo;
  String? _currentTaggerId;
  GeoPoint? _freezeOrigin;
  DateTime? _freezeUntil;
  bool _freezePopupShown = false;
  Set<Polygon> _fieldPolygons = {};
  List<_PlayerInfo> get _otherPlayers =>
      _players.where((p) => !p.isMe && !p.caught).toList();
  List<LatLng> _fieldPoints = [];
  bool _outsideNotified = false;
  bool _navigatedByGameEnd = false;
  bool _iAmCaught = false;
  bool _showCaughtOverlay = false;
  int _ntpOffset = 0;

  bool get _isCurrentlyFrozen {
    final until = _freezeUntil;
    if (until == null) return false;
    return _now.isBefore(until);
  }

  bool get _isHost {
    final lobby = _latestLobby ?? widget.args.lobby;
    return lobby.owner.userId == widget.args.currentUserId;
  }

  bool get _allRunnersCaught {
    // プレイヤーからRUNNERだけを取り出す
    final runners = _players.where((p) => p.role == 'RUNNER').toList();
    if (runners.isEmpty) return false;
    // 全員 caught == true なら true
    return runners.every((p) => p.caught);
  }

  bool get _canHostEndGame {
    // タイムアップ or 全RUNNER確保
    return _remainingSeconds <= 0 || _allRunnersCaught;
  }
  Future<void> _endGameForAll() async {
    final lobby = _latestLobby ?? widget.args.lobby;
    final gameId = lobby.gameId;

    if (gameId == null || gameId.isEmpty) return;

    // 念のためホスト以外は弾く
    if (!_isHost) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ホストだけがゲーム終了できます')),
        );
      }
      return;
    }

    try {
      await _partyService.updateGameStatus(
        gameId: gameId,
        status: 'FINISHED',
        partyId: lobby.partyId,
      );
      // 自分も即ホームに戻る（他の人は watch で自動遷移）
      if (mounted && !_navigatedByGameEnd) {
        _navigatedByGameEnd = true;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ゲーム終了に失敗しました: $e')),
      );
    }
  }


  @override
  void initState() {
    super.initState();
    _latestLobby = widget.args.lobby;
    _initializeAsync();
    _setupNotifications();
    
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
    _startItemsWatch();
    _refreshLobbyRole();
  }
  // ★追加: 通知セットアップメソッド
  Future<void> _setupNotifications() async {
    final messaging = FirebaseMessaging.instance;
    
    // 1. 通知権限のリクエスト
    await messaging.requestPermission();

    // 2. ゲームIDのトピックを購読
    final gameId = widget.args.lobby.gameId;
    if (gameId != null) {
      await messaging.subscribeToTopic('game_$gameId');
    }

    // 3. アプリ起動中の通知受信リスナー
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async{
      if (message.notification != null) {
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 1000); // 1000ミリ秒（1秒）振動
        }
        // スナックバーで表示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${message.notification!.title}: ${message.notification!.body}'),
              backgroundColor: Colors.blueAccent,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    });
  }

  // ★追加: Cloud Functions を呼ぶヘルパーメソッド
  Future<void> _sendNotification(String title, String body) async {
    final gameId = widget.args.lobby.gameId;
    if (gameId == null) return;

    try {
      await FirebaseFunctions.instance.httpsCallable('notifyGameEvent').call({
        'gameId': gameId,
        'title': title,
        'body': body,
      });
    } catch (e) {
      debugPrint('Failed to send notification: $e');
    }
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

    final effectiveRole = _effectiveRole(_myRoleCode);
    if (_isCurrentlyFrozen && _freezeOrigin != null) {
      final freezeDistance = Geolocator.distanceBetween(
        _freezeOrigin!.latitude,
        _freezeOrigin!.longitude,
        current.latitude,
        current.longitude,
      );
      if (freezeDistance > 5) {
        if (!_freezePopupShown && mounted) {
          _freezePopupShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('現在フリーズ中のため動けません')),
          );
        }
        return;
      }
    } else if (_freezePopupShown) {
      _freezePopupShown = false;
    }

      setState(() {
        _currentLatLng = current;
      });
      _updateTaggerGauge(current);
      _checkTrapCollision(current, effectiveRole);

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
      _tryPickupNearbyItems(current);
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
      List<String>? myItemsList;
      GeoPoint? taggerGeo;

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

        if (role == 'TAGGER') {
          taggerGeo = geo;
          _currentTaggerId = doc.id;
        }

        if (isMe) {
          myGeo = geo;
          myRole = role;
          myCaught = caught;
          final rawItems = (data['items'] as List<dynamic>?) ?? const [];
          myItemsList = rawItems.cast<String>();
          final freezeUntil = (data['freezeUntil'] as Timestamp?)?.toDate();
          final freezeOrigin = data['freezeOrigin'] as GeoPoint?;
          _freezeUntil = freezeUntil;
          _freezeOrigin = freezeOrigin;
          if (!_isCurrentlyFrozen) {
            _freezePopupShown = false;
          }
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

    final totalRunners =
          players.where((p) => p.role == 'RUNNER').length;
    final captured =
          players.where((p) => p.role == 'RUNNER' && p.caught).length;

    // ★ 逃走側が捕まったときの通知（1回だけ）
    if (myRole == 'RUNNER' && myCaught && !_alreadyNotifiedCaught) {
      _alreadyNotifiedCaught = true;
      if (!mounted) return;

        setState(() {
          _iAmCaught = true;        // ← 観戦モードに入ったことを覚えておく
          _showCaughtOverlay = true;  // ← オーバーレイ表示フラグを立てる
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('捕まってしまいました…！')),
        );
      }
      // if (mounted) {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     const SnackBar(content: Text('捕まってしまいました…！')),
      //   );
      //   //Game Over時の画面遷移
      //   Future.microtask(() {
      //     if (!mounted) return;
      //     Navigator.of(context).pushReplacementNamed(
      //       AppRoutes.gameOver, // ←あなたのルート名に合わせて変更
      //       arguments: GameOverPageArgs(
      //         lobby: _latestLobby ?? widget.args.lobby,
      //         gameId: widget.args.gameId,
      //         currentUserId: widget.args.currentUserId,
      //       ),
      //     );
      //   });
      //}

    if (!mounted) return;

    // 状態更新
    final hasFreezeItem =
        (myItemsList ?? const <String>[]).contains('FREEZE_TAGGER');
    final freezeReady = hasFreezeItem &&
        myGeo != null &&
        taggerGeo != null &&
        Geolocator.distanceBetween(
              myGeo.latitude,
              myGeo.longitude,
              taggerGeo.latitude,
              taggerGeo.longitude,
            ) <=
            5;

    setState(() {
      _players
        ..clear()
        ..addAll(players);
      _myLastGeo = myGeo;
      _myRoleCode = myRole;
      _totalRunners = totalRunners;   // ★追加
      _capturedCount = captured;  
      _items
        ..clear()
        ..addAll(myItemsList ?? const []);
      _freezeReady = freezeReady;
      _lastTaggerGeo = taggerGeo;
      if (_effectiveRole(myRole) != 'TAGGER') {
        _taggerGauge = 0;
        _lastGaugePoint = null;
      }
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

  void _startItemsWatch() {
    final lobby = _latestLobby ?? widget.args.lobby;
    final gameId = lobby.gameId;
    if (gameId == null || gameId.isEmpty) return;

    _itemsSub = FirebaseFirestore.instance
        .collection('gameSessions')
        .doc(gameId)
        .collection('items')
        .snapshots()
        .listen(
      (snapshot) {
        final allowedTypes = _visibleItemTypesForRole(_role);
        final allItems = snapshot.docs.map(_GameItem.fromDoc).toList();
        final items =
            allItems.where((item) => allowedTypes.contains(item.type)).toList();
        if (!mounted) return;
        final markers = _buildItemMarkers(items);
        setState(() {
          _gameItems
            ..clear()
            ..addAll(allItems);
          _itemMarkers
            ..clear()
            ..addAll(markers);
          _armedTraps
            ..clear()
            ..addAll(
              allItems.where(
                (item) =>
                    item.type == 'TRAP' && item.state == _ItemStates.armed,
              ),
            );
          _refreshCombinedMarkers();
        });
      },
      onError: (error, stack) {
        debugPrint('Failed to watch items: $error\n$stack');
      },
    );
  }

  Set<Marker> _buildItemMarkers(List<_GameItem> items) {
    final markers = <Marker>{};
    for (final item in items) {
      final shouldShow = item.state == _ItemStates.available ||
          (item.type == 'TRAP' && item.state == _ItemStates.armed);
      if (!shouldShow) continue;
      final hue = _itemHueByType(item.type);
      markers.add(
        Marker(
          markerId: MarkerId('item_${item.itemId}'),
          position: LatLng(item.lat, item.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title: _itemLabelByType(item.type),
            snippet: 'アイテムを拾えます',
          ),
        ),
      );
    }
    return markers;
  }

  double _itemHueByType(String type) {
    switch (type) {
      case 'FREEZE_TAGGER':
        return BitmapDescriptor.hueAzure;
      case 'SEE_TAGGER':
        return BitmapDescriptor.hueGreen;
      case 'FAKE_LOCATION':
        return BitmapDescriptor.hueCyan;
      case 'TRAP':
        return BitmapDescriptor.hueRed;
      case 'FAKE_LOCATION_TAGGER':
        return BitmapDescriptor.hueMagenta;
      default:
        return BitmapDescriptor.hueRose;
    }
  }

  String _itemLabelByType(String type) {
    switch (type) {
      case 'FREEZE_TAGGER':
        return 'フリーズ鬼';
      case 'SEE_TAGGER':
        return '鬼を探知';
      case 'FAKE_LOCATION':
        return 'フェイク位置';
      case 'TRAP':
        return 'トラップ';
      case 'FAKE_LOCATION_TAGGER':
        return 'フェイク位置(鬼)';
      default:
        return type;
    }
  }
  
  bool _isItemEnabled(String type) {
    if (_iAmCaught) {
      return false;
    }
    if (_role == PartyMemberRole.runner) {
      if (type == 'FREEZE_TAGGER') {
        return _freezeReady;
      }
      if (type == 'FAKE_LOCATION') {
        return false;
      }
      return type != 'TRAP';
    } else if (_role == PartyMemberRole.tagger) {
      if (type == 'TRAP') {
        return true;
      }
      if (type == 'FAKE_LOCATION_TAGGER') {
        return false;
      }
      return type != 'FAKE_LOCATION';
    }
    return false;
  }

  Future<void> _tryPickupNearbyItems(LatLng current) async {
    if (_isPickingItem) return;
    final role = _effectiveRole(_myRoleCode);
    if (_items.length >= 2) return;
    if (role == 'PENDING') return;

    final allowedTypes = role == 'TAGGER'
        ? _taggerVisibleItemTypes
        : _runnerVisibleItemTypes;

    final nearby = _gameItems.where(
      (item) =>
          item.state == 'AVAILABLE' &&
          allowedTypes.contains(item.type) &&
          _itemVisibleToRole(item, role),
    );
    for (final item in nearby) {
      final distance = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        item.lat,
        item.lng,
      );
      if (distance <= 5) {
        _isPickingItem = true;
        try {
          await _pickupItem(item);
        } finally {
          _isPickingItem = false;
        }
        break;
      }
    }
  }

  void _handleItemPressed(String itemType) {
    if (!_items.contains(itemType)) {
      return;
    }
    if (!_isItemEnabled(itemType)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('条件を満たしていません')),
      );
      return;
    }
    if (_isUsingItem) {
      return;
    }
    _useItem(itemType);
  }

  Future<void> _useItem(String itemType) async {
    _isUsingItem = true;
    try {
      switch (itemType) {
        case 'SEE_TAGGER':
          await _revealTaggerLocation();
          break;
        case 'FREEZE_TAGGER':
          await _applyFreezeToTagger();
          break;
        case 'TRAP':
          await _deployTrap();
          break;
        default:
          if (!mounted) break;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$itemType はまだ実装されていません')),
          );
          break;
      }
      await _consumeItem(itemType);
    } catch (e, s) {
      debugPrint('Failed to use item: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('アイテムの使用に失敗しました: $e')),
        );
      }
    } finally {
      _isUsingItem = false;
    }
  }

  Future<void> _revealTaggerLocation() async {
    final lobby = _latestLobby ?? widget.args.lobby;
    final gameId = lobby.gameId;
    if (gameId == null || gameId.isEmpty) return;

    final query = await FirebaseFirestore.instance
        .collection('gameSessions')
        .doc(gameId)
        .collection('players')
        .where('role', isEqualTo: 'TAGGER')
        .get();

    final markers = <Marker>{};
    for (final doc in query.docs) {
      final data = doc.data();
      final geo = data['lastLocation'] as GeoPoint?;
      if (geo == null) continue;
      var position = LatLng(geo.latitude, geo.longitude);
      final taggerItems =
          List<String>.from((data['items'] as List<dynamic>?) ?? const []);
      if (taggerItems.contains('FAKE_LOCATION_TAGGER')) {
        position = await _maybeApplyTaggerFakeLocation(
          realPosition: position,
          taggerId: doc.id,
        );
      }
      markers.add(
        Marker(
          markerId: MarkerId('reveal_${doc.id}'),
          position: position,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: '鬼の位置'),
        ),
      );
    }

    if (markers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('鬼の位置を取得できませんでした')),
        );
      }
      return;
    }

    setState(() {
      _effectMarkers
        ..clear()
        ..addAll(markers);
      _refreshCombinedMarkers();
    });

    _revealTimer?.cancel();
    _revealTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        _effectMarkers.clear();
        _refreshCombinedMarkers();
      });
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('鬼の位置を5秒間表示します')),
      );
    }
  }
  Future<void> _triggerListenAbility() async {
    if (_taggerGauge < 1 || _isListeningAbilityActive) {
      return;
    }
    final lobby = _latestLobby ?? widget.args.lobby;
    final gameId = lobby.gameId;
    if (gameId == null || gameId.isEmpty) return;

    setState(() {
      _isListeningAbilityActive = true;
      _taggerGauge = 0;
      _lastGaugePoint = _currentLatLng;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final snapshot = await firestore
          .collection('gameSessions')
          .doc(gameId)
          .collection('players')
          .where('role', isEqualTo: 'RUNNER')
          .get();
      final markers = <Marker>{};
      final consumeFutures = <Future<void>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final geo = data['lastLocation'] as GeoPoint?;
        if (geo == null) continue;
        var markerLatLng = LatLng(geo.latitude, geo.longitude);
        final runnerItems =
            List<String>.from((data['items'] as List<dynamic>?) ?? const []);
        final hasFakeLocation = runnerItems.contains('FAKE_LOCATION');
        if (hasFakeLocation) {
          markerLatLng = _generateFakeLocation(markerLatLng);
          consumeFutures.add(_consumeItemForRunner(
            gameId: gameId,
            playerId: doc.id,
            itemType: 'FAKE_LOCATION',
          ));
        }
        markers.add(
          Marker(
            markerId: MarkerId('listen_${doc.id}'),
            position: markerLatLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange,
            ),
            infoWindow: InfoWindow(
              title: data['displayName'] as String? ?? 'Runner',
            ),
          ),
        );
      }
      if (consumeFutures.isNotEmpty) {
        await Future.wait(consumeFutures);
      }
      if (markers.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('逃走者の位置を取得できませんでした')),
          );
        }
      } else {
        setState(() {
          _effectMarkers
            ..clear()
            ..addAll(markers);
          _refreshCombinedMarkers();
        });
        _revealTimer?.cancel();
        _revealTimer = Timer(const Duration(seconds: 5), () {
          if (!mounted) return;
          setState(() {
            _effectMarkers.clear();
            _refreshCombinedMarkers();
          });
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('逃走者の位置を5秒間表示します')),
          );
        }
      }
    } catch (e, s) {
      debugPrint('Failed to trigger listen ability: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('リッスン発動に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isListeningAbilityActive = false;
        });
      } else {
        _isListeningAbilityActive = false;
      }
    }
  }

  Future<void> _consumeItem(String itemType) async {
    final lobby = _latestLobby ?? widget.args.lobby;
    final gameId = lobby.gameId;
    if (gameId == null || gameId.isEmpty) return;
    final playerId = widget.args.currentUserId;
    final removed = await _removeItemFromPlayerDoc(
      gameId: gameId,
      playerId: playerId,
      itemType: itemType,
    );
    if (!removed) {
      throw Exception('アイテムが見つかりません');
    }
    await _markUsedItemDoc(gameId, playerId, itemType);

    if (mounted) {
      setState(() {
        _items.remove(itemType);
        if (itemType == 'FREEZE_TAGGER') {
          _freezeReady = false;
        }
      });
    }
  }

  void _updateTaggerGauge(LatLng current) {
    final role = _effectiveRole(_myRoleCode);
    if (role != 'TAGGER' || _iAmCaught) {
      _lastGaugePoint = null;
      return;
    }
    if (_isListeningAbilityActive) {
      return;
    }
    final prev = _lastGaugePoint;
    _lastGaugePoint = current;
    if (prev == null) {
      return;
    }
    final distance = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      current.latitude,
      current.longitude,
    );
    if (distance <= 0) return;
    final increment = distance / 500.0; // 5m で 1%
    setState(() {
      _taggerGauge = (_taggerGauge + increment).clamp(0.0, 1.0);
    });
  }

  Future<void> _applyFreezeToTagger() async {
    if (_lastTaggerGeo == null || _myLastGeo == null || _currentTaggerId == null) {
      throw Exception('鬼の位置を取得できませんでした');
    }
    final distance = Geolocator.distanceBetween(
      _myLastGeo!.latitude,
      _myLastGeo!.longitude,
      _lastTaggerGeo!.latitude,
      _lastTaggerGeo!.longitude,
    );
    if (distance > 5) {
      throw Exception('鬼の近くにいません');
    }
    final lobby = _latestLobby ?? widget.args.lobby;
    final gameId = lobby.gameId;
    if (gameId == null || gameId.isEmpty) {
      throw Exception('ゲームIDが不明です');
    }
    final firestore = FirebaseFirestore.instance;
    final taggerRef = firestore
        .collection('gameSessions')
        .doc(gameId)
        .collection('players')
        .doc(_currentTaggerId);

    await firestore.runTransaction((tx) async {
      final snap = await tx.get(taggerRef);
      if (!snap.exists) {
        throw Exception('鬼のデータが見つかりません');
      }
      final now = DateTime.now();
      tx.update(taggerRef, {
        'freezeOrigin': GeoPoint(_lastTaggerGeo!.latitude, _lastTaggerGeo!.longitude),
        'freezeUntil': Timestamp.fromDate(now.add(const Duration(seconds: 5))),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('鬼を5秒間フリーズさせました')),
      );
    }
  }

  Future<void> _deployTrap() async {
    if (_myLastGeo == null) {
      throw Exception('現在地を取得できません');
    }
    final lobby = _latestLobby ?? widget.args.lobby;
    final gameId = lobby.gameId;
    if (gameId == null || gameId.isEmpty) {
      throw Exception('ゲームIDが不明です');
    }
    final playerId = widget.args.currentUserId;
    final firestore = FirebaseFirestore.instance;
    final trapDoc = await _findOwnedItemDoc(
      gameId: gameId,
      playerId: playerId,
      type: 'TRAP',
    );
    if (trapDoc == null) {
      throw Exception('配置できるトラップがありません');
    }

    await firestore.runTransaction((tx) async {
      tx.update(trapDoc, {
        'state': _ItemStates.armed,
        'lat': _myLastGeo!.latitude,
        'lng': _myLastGeo!.longitude,
        'armedAt': FieldValue.serverTimestamp(),
        'armedBy': playerId,
      });
      final playerRef = firestore
          .collection('gameSessions')
          .doc(gameId)
          .collection('players')
          .doc(playerId);
      final snap = await tx.get(playerRef);
      final items =
          List<String>.from((snap.data()?['items'] as List<dynamic>?) ?? const []);
      final removed = items.remove('TRAP');
      if (removed) {
        tx.update(playerRef, {
          'items': items,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    if (mounted) {
      setState(() {
        _items.remove('TRAP');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('トラップを設置しました')),
      );
    }
  }

  Future<void> _markUsedItemDoc(
    String gameId,
    String playerId,
    String itemType,
  ) async {
    final query = await FirebaseFirestore.instance
        .collection('gameSessions')
        .doc(gameId)
        .collection('items')
        .where('type', isEqualTo: itemType)
        .where('pickedBy', isEqualTo: playerId)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return;
    await query.docs.first.reference.update({
      'state': 'USED',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<DocumentReference<Map<String, dynamic>>?> _findOwnedItemDoc({
    required String gameId,
    required String playerId,
    required String type,
  }) async {
    final query = await FirebaseFirestore.instance
        .collection('gameSessions')
        .doc(gameId)
        .collection('items')
        .where('type', isEqualTo: type)
        .where('pickedBy', isEqualTo: playerId)
        .where('state', isEqualTo: _ItemStates.picked)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    return query.docs.first.reference;
  }

  Future<bool> _removeItemFromPlayerDoc({
    required String gameId,
    required String playerId,
    required String itemType,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final playerRef = firestore
        .collection('gameSessions')
        .doc(gameId)
        .collection('players')
        .doc(playerId);

    return firestore.runTransaction((tx) async {
      final snap = await tx.get(playerRef);
      if (!snap.exists) return false;
      final items =
          List<String>.from((snap.data()?['items'] as List<dynamic>?) ?? const []);
      final removed = items.remove(itemType);
      if (removed) {
        tx.update(playerRef, {
          'items': items,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      return removed;
    });
  }

  Future<void> _consumeItemForRunner({
    required String gameId,
    required String playerId,
    required String itemType,
  }) async {
    final removed = await _removeItemFromPlayerDoc(
      gameId: gameId,
      playerId: playerId,
      itemType: itemType,
    );
    if (removed) {
      await _markUsedItemDoc(gameId, playerId, itemType);
    }
  }

  Future<void> _triggerTrap(_GameItem trap) async {
    final lobby = _latestLobby ?? widget.args.lobby;
    final gameId = lobby.gameId;
    final playerId = widget.args.currentUserId;
    if (gameId == null || gameId.isEmpty) return;
    if (_isCurrentlyFrozen) return;

    final firestore = FirebaseFirestore.instance;
    final trapRef = firestore
        .collection('gameSessions')
        .doc(gameId)
        .collection('items')
        .doc(trap.itemId);
    final playerRef = firestore
        .collection('gameSessions')
        .doc(gameId)
        .collection('players')
        .doc(playerId);

    await firestore.runTransaction((tx) async {
      final trapSnap = await tx.get(trapRef);
      if (!trapSnap.exists) return;
      final trapState = trapSnap.data()?['state'] as String? ?? '';
      if (trapState != _ItemStates.armed) return;
      final now = DateTime.now();
      tx.update(trapRef, {
        'state': _ItemStates.used,
        'triggeredBy': playerId,
        'triggeredAt': Timestamp.fromDate(now),
      });
      tx.update(playerRef, {
        'freezeOrigin': GeoPoint(trap.lat, trap.lng),
        'freezeUntil': Timestamp.fromDate(now.add(const Duration(seconds: 5))),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (mounted) {
      setState(() {
        _freezeOrigin = GeoPoint(trap.lat, trap.lng);
        _freezeUntil = DateTime.now().add(const Duration(seconds: 5));
        _freezePopupShown = false;
        _armedTraps.removeWhere((t) => t.itemId == trap.itemId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('トラップにかかりました！5秒間動けません')),
      );
    }
  }

  Future<LatLng> _maybeApplyTaggerFakeLocation({
    required LatLng realPosition,
    required String taggerId,
  }) async {
    final lobby = _latestLobby ?? widget.args.lobby;
    final gameId = lobby.gameId;
    if (gameId == null || gameId.isEmpty) {
      return realPosition;
    }
    final removed = await _removeItemFromPlayerDoc(
      gameId: gameId,
      playerId: taggerId,
      itemType: 'FAKE_LOCATION_TAGGER',
    );
    if (!removed) {
      return realPosition;
    }
    await _markUsedItemDoc(gameId, taggerId, 'FAKE_LOCATION_TAGGER');
    return _generateFakeLocation(realPosition);
  }

  LatLng _generateFakeLocation(LatLng base) {
    const minMeters = 30.0;
    const maxMeters = 80.0;
    final distance = minMeters + _random.nextDouble() * (maxMeters - minMeters);
    final bearing = _random.nextDouble() * 2 * pi;
    final deltaLatMeters = distance * cos(bearing);
    final deltaLngMeters = distance * sin(bearing);
    const metersPerDegree = 111320.0;
    final deltaLat = deltaLatMeters / metersPerDegree;
    final cosLat = cos(base.latitude * pi / 180).abs();
    final lngScale = cosLat < 0.0001 ? 0.0001 : cosLat;
    final deltaLng = deltaLngMeters / (metersPerDegree * lngScale);
    final fakeLat = base.latitude + deltaLat;
    final fakeLng = base.longitude + deltaLng;
    return LatLng(fakeLat, fakeLng);
  }

  Future<void> _pickupItem(_GameItem item) async {
    final lobby = _latestLobby ?? widget.args.lobby;
    final gameId = lobby.gameId;
    if (gameId == null || gameId.isEmpty) return;
    final playerId = widget.args.currentUserId;
    final firestore = FirebaseFirestore.instance;
    final gameRef = firestore.collection('gameSessions').doc(gameId);
    final playerRef = gameRef.collection('players').doc(playerId);
    final itemRef = gameRef.collection('items').doc(item.itemId);

    try {
      await firestore.runTransaction((tx) async {
        final playerSnap = await tx.get(playerRef);
        final itemSnap = await tx.get(itemRef);
        if (!playerSnap.exists || !itemSnap.exists) {
          throw Exception('データを取得できませんでした');
        }
        final itemData = itemSnap.data();
        if ((itemData?['state'] as String?) != 'AVAILABLE') {
          throw Exception('このアイテムは取得済みです');
        }

        final existing =
            List<String>.from((playerSnap.data()?['items'] as List<dynamic>?) ?? const []);
        if (existing.length >= 2) {
          throw Exception('これ以上アイテムを持てません');
        }

        existing.add(item.type);

        tx.update(playerRef, {
          'items': existing,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.update(itemRef, {
          'state': 'PICKED',
          'pickedBy': playerId,
          'pickedAt': FieldValue.serverTimestamp(),
        });
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_itemLabelByType(item.type)}を入手しました')),
      );
    } catch (e, s) {
      debugPrint('Failed to pickup item: $e\n$s');
    }
  }

  bool _itemVisibleToRole(_GameItem item, String role) {
    if (item.visibility == 'TAGGER' && role != 'TAGGER') {
      return false;
    }
    if (item.visibility == 'RUNNER' && role != 'RUNNER') {
      return false;
    }
    return true;
  }

  String _effectiveRole(String? snapshotRole) {
    if (snapshotRole == null || snapshotRole == 'PENDING') {
      switch (_role) {
        case PartyMemberRole.tagger:
          return 'TAGGER';
        case PartyMemberRole.runner:
          return 'RUNNER';
        case PartyMemberRole.pending:
          return 'PENDING';
      }
    }
    return snapshotRole;
  }

    void _updateCatchAvailability({
  required GeoPoint? myGeo,
  required String? myRole,
  required QuerySnapshot<Map<String, dynamic>> snapshot,
}) {
  // Firestore側のロールが PENDING でも、
  // ロビー情報 (_role) が鬼なら TAGGER とみなす
  final effectiveRole = _effectiveRole(myRole);

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
  // ★修正: リストをコピーして、別のリストとして固定する
    // これで裏で _nearRunnerRefs が変わってもクラッシュしなくなります
    final targets = List<DocumentReference<Map<String, dynamic>>>.from(_nearRunnerRefs);
    // 近くにいる RUNNER 全員を捕まえたことにする
    for (final ref in targets) {
      await ref.update({
        'caught': true,
        'caughtAt': FieldValue.serverTimestamp(),
        'caughtBy': widget.args.currentUserId,
      });
    }
    final myName = _players.firstWhere(
      (p) => p.isMe,
      orElse: () => const _PlayerInfo(
        id: '',
        name: '不明なプレイヤー',
        position: LatLng(0, 0),
        role: '',
        isMe: true,
        inside: false,
        caught: false,
      ),
    ).name;
    await _sendNotification('確保！', '$myName が逃走者を捕まえました！');
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
      // 捕まったプレイヤーは表示しない
      if (p.caught) continue;
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
      _playerMarkers
        ..clear()
        ..addAll(newMarkers);
      _refreshCombinedMarkers();
    });
  }

  void _refreshCombinedMarkers() {
    _markers
      ..clear()
      ..addAll(_playerMarkers)
      ..addAll(_itemMarkers)
      ..addAll(_effectMarkers);
  }

  void _checkTrapCollision(LatLng current, String effectiveRole) {
    if (effectiveRole != 'RUNNER') return;
    if (_armedTraps.isEmpty) return;
    for (final trap in _armedTraps) {
      final distance = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        trap.lat,
        trap.lng,
      );
      if (distance <= 5) {
        _triggerTrap(trap);
        break;
      }
    }
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

  void _checkFieldBoundary(LatLng point) async {
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
      if (await Vibration.hasVibrator() ?? false) {
        // パターン振動も可能 (待機500ms, 振動1000ms, 待機500ms, 振動1000ms...)
        Vibration.vibrate(pattern: [500, 1000, 500, 1000]); 
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在地はエリア外です')),
      );
      String myName = 'プレイヤー';
      try {
        // 1. 最新のロビー情報があればそれを使う
        // 2. なければ画面遷移時に受け取ったロビー情報を使う
        final currentLobby = _latestLobby ?? widget.args.lobby;
        
        final me = currentLobby.allMembers.firstWhere(
          (m) => m.userId == widget.args.currentUserId,
        );
        myName = me.name;
      } catch (e) {
        debugPrint('名前の取得に失敗しました: $e');
      }
     await _sendNotification('エリア外警告', '$myName さんがエリア外に出ました！');
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
    _itemsSub?.cancel();
    _revealTimer?.cancel();
    final gameId = widget.args.lobby.gameId;
    if (gameId != null) {
      FirebaseMessaging.instance.unsubscribeFromTopic('game_$gameId');
    }
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
  _gameSessionSub =
      _partyService.watchGameSession(gameId).listen((session) {
    if (!mounted) return;
    setState(() => _gameSession = session);
    _updateTimeFromSession();

    final status = session?.status;

    if (!_navigatedByGameEnd && status != null) {
      if (status == 'FINISHED') {
        _navigatedByGameEnd = true;

        // ★ 勝敗判定
        final taggersWin = _allRunnersCaught;
        final myRole = _role;
        final isMyTeamWin =
            (taggersWin && myRole == PartyMemberRole.tagger) ||
            (!taggersWin && myRole == PartyMemberRole.runner);

        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.gameOver,   // ← 既存のルートをそのまま利用
          (route) => false,
          arguments: GameOverPageArgs(
            lobby: _latestLobby ?? widget.args.lobby,
            currentUserId: widget.args.currentUserId,
            gameId: widget.args.gameId,
            taggersWin: taggersWin,
            isMyTeamWin: isMyTeamWin,
            capturedCount: _capturedCount,
            totalRunners: _totalRunners,
          ),
        );
      } else if (status == 'ABORTED') {
        // 中断時はとりあえずホームに戻す
        _navigatedByGameEnd = true;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
          (route) => false,
        );
      }
    }
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
    if (_isHost) {
    final status = session.status;
    if (status != 'FINISHED' && (remaining <= 0 || _allRunnersCaught)) {
      // タイムアップ or 全員確保 なのにまだ FINISHED でなければ更新する
      _partyService.updateGameStatus(
        gameId: widget.args.gameId,
        status: 'FINISHED',
        partyId: widget.args.lobby.partyId,
      );
    }
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

Future<void> _debugCatchAllRunners() async {
  final lobby = _latestLobby ?? widget.args.lobby;
  final gameId = lobby.gameId;
  if (gameId == null || gameId.isEmpty) return;

  // ホスト以外は念のため弾く
  if (!_isHost) return;

  try {
    final batch = FirebaseFirestore.instance.batch();
    for (final p in _players) {
      if (p.role != 'RUNNER') continue;
      final ref = FirebaseFirestore.instance
          .collection('gameSessions')
          .doc(gameId)
          .collection('players')
          .doc(p.id);
      batch.update(ref, {
        'caught': true,
        'caughtAt': FieldValue.serverTimestamp(),
        'caughtBy': widget.args.currentUserId,
      });
    }
    await batch.commit();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('デバッグ：全員捕まえました')),
    );

    // ★ここでゲーム終了まで進めてみる
    await _endGameForAll();

  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('デバッグ全員捕獲に失敗しました: $e')),
    );
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

    final totalRunners = _totalRunners;
    final remainingPlayers =
        (totalRunners - _capturedCount).clamp(0, totalRunners);

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
                // ★追加：捕まったときのモックアップオーバーレイ
                if (_showCaughtOverlay)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.5),
                      child: Align(
                        alignment: const Alignment(0, -0.2), // ← ★ ここで位置調整（-1.0 〜 +1.0）
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.8,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.sentiment_dissatisfied,
                                size: 70,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'あなたは捕まってしまいました！',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'ゲームが終わるまで、他のプレイヤーを観戦できます。',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    backgroundColor: _palette.accent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _showCaughtOverlay = false;
                                    });
                                  },
                                  child: const Text(
                                    '観戦する',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
            
                        if (_iAmCaught) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'あなたは捕まりました（観戦モード）',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],

                        if (_role == PartyMemberRole.tagger && !_iAmCaught) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _GaugeAbilityButton(
                              progress: _taggerGauge.clamp(0.0, 1.0),
                              enabled: _taggerGauge >= 1 && !_isListeningAbilityActive,
                              onPressed: _triggerListenAbility,
                              label: 'リッスン',
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        _StatsBar(
                          accent: _palette.accent,
                          capturedCount: _capturedCount,
                          remainingPlayers: remainingPlayers,
                          items: _items,
                          itemLabelResolver: _itemLabelByType,
                          canUseItems: !_iAmCaught,
                          itemEnabledResolver: _isItemEnabled,
                          onItemPressed: _handleItemPressed,
                        ),

                        // 鬼の Catch ボタン
                        if (_role == PartyMemberRole.tagger) ...[
                          const SizedBox(height: 12),
                          _CatchButton(
                            accent: _palette.accent,
                            enabled: _canCatch,
                            onPressed: _onCatchPressed,
                          ),
                        ],

                        if (_isHost && kDebugMode) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _debugCatchAllRunners,
                              child: const Text('【デバッグ】全員捕まえた状態にする'),
                            ),
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
  final bool canUseItems;
  final ValueChanged<String>? onItemPressed;
  final String Function(String) itemLabelResolver;
  final bool Function(String) itemEnabledResolver;

  const _StatsBar({
    required this.accent,
    required this.capturedCount,
    required this.remainingPlayers,
    required this.items,
    required this.itemLabelResolver,
    required this.itemEnabledResolver,
    this.canUseItems = false,
    this.onItemPressed,
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
                    (item) => ActionChip(
                      label: Text(itemLabelResolver(item)),
                      backgroundColor: accent.withOpacity(
                        canUseItems && itemEnabledResolver(item) ? 0.2 : 0.08,
                      ),
                      labelStyle: TextStyle(
                        color: canUseItems && itemEnabledResolver(item)
                            ? accent
                            : Colors.black45,
                        fontWeight: FontWeight.bold,
                      ),
                      onPressed: canUseItems &&
                              itemEnabledResolver(item) &&
                              onItemPressed != null
                          ? () => onItemPressed!(item)
                          : null,
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

class _GaugeAbilityButton extends StatelessWidget {
  final double progress;
  final bool enabled;
  final VoidCallback onPressed;
  final String label;

  const _GaugeAbilityButton({
    required this.progress,
    required this.enabled,
    required this.onPressed,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    const size = 80.0;
    final activeColor = const Color.fromARGB(255, 70, 156, 248);
    final inactiveColor = Colors.tealAccent.withOpacity(0.35);
    final baseGlow = Colors.teal.withOpacity(0.25);
    final borderColor = enabled ? Colors.white : Colors.white60;
    return Column(
      children: [
        GestureDetector(
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: baseGlow,
                    border: Border.all(color: borderColor, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: activeColor.withOpacity(enabled ? 0.6 : 0.2),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                CircularProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  strokeWidth: 6,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    enabled ? activeColor : inactiveColor,
                  ),
                ),
                Icon(
                  Icons.radar,
                  color: enabled ? Colors.white : Colors.white70,
                  size: 32,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(enabled ? 0.95 : 0.65),
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
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