import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../data/services/party_service.dart';
import '../../routes.dart';

class RoomGamePageArgs {
  final PartyLobbyData lobby;
  final String currentUserId;
  final String? gameId;

  const RoomGamePageArgs({
    required this.lobby,
    required this.currentUserId,
    this.gameId,
  });
}

class RoomGamePage extends StatefulWidget {
  final RoomGamePageArgs args;

  const RoomGamePage({super.key, required this.args});

  @override
  State<RoomGamePage> createState() => _RoomGamePageState();
}

class _RoomGamePageState extends State<RoomGamePage> {
  final PartyService _partyService = PartyService();
  late final PartyMemberRole _role;
  late final _RolePalette _palette;

  Timer? _countdownTimer;
  int _countdown = 3;
  bool _showGo = false;

  int _capturedCount = 0;
  final Map<String, GameItem> _visibleItems = {};
  List<PlayerItem> _playerItems = const [];
  List<PlayerLocation> _taggerLocations = const [];
  late int _remainingSeconds;
  Timer? _gameTimer;
  String? _initErrorMessage;
  StreamSubscription<List<GameItem>>? _itemsSub;
  StreamSubscription<List<PlayerItem>>? _playerItemsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _playerDocSub;
  StreamSubscription<List<PlayerLocation>>? _taggerLocationsSub;
  StreamSubscription<List<GameTrap>>? _trapsSub;
  String? _playerId;
  bool _isPickingItem = false;
  bool _isUsingSeeTagger = false;
  bool _isFreezingTagger = false;
  bool _isUsingTaggerAbility = false;
  bool _isPlacingTrap = false;
  Timer? _taggerMarkerTimer;
  Timer? _runnerMarkerTimer;
  StreamSubscription<Position>? _positionSub;
  final Map<String, GameTrap> _traps = {};
  bool _isTrapped = false;
  LatLng? _trapOrigin;
  Timer? _trapReleaseTimer;
  Timer? _trapCountdownTimer;
  int _trapRemainingSeconds = 0;
  bool _trapMovementDialogVisible = false;
  bool _isFrozen = false;
  LatLng? _freezeOrigin;
  Timer? _freezeReleaseTimer;
  Timer? _freezeCountdownTimer;
  int _freezeRemainingSeconds = 0;
  bool _freezeMovementDialogVisible = false;
  bool _freezeDialogVisible = false;

  GoogleMapController? _mapController;
  LatLng? _currentLatLng;
  LatLng? _lastGaugeLatLng;
  double _gaugePercent = 0;
  double _gaugeDistanceBuffer = 0;
  bool _isLocating = true;
  String? _locationError;
  final Set<Marker> _markers = {};
  Set<Polygon> _fieldPolygons = {};

  @override
  void initState() {
    super.initState();
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
    if (_initErrorMessage == null) {
      _startCountdown();
      _loadCurrentLocation();
      _loadFieldPolygon();
      final gameId = widget.args.gameId;
      if (gameId != null && _role != PartyMemberRole.pending) {
        _fetchPlayerId(gameId);
        _subscribeToGameItems(gameId);
        if (_role == PartyMemberRole.runner) {
          _subscribeToTaggerLocations(gameId);
        }
        _subscribeToTraps(gameId);
        if (_role != PartyMemberRole.pending) {
          final playerId = _playerId;
          if (playerId != null) {
            _subscribeToPlayerDoc(gameId, playerId);
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _gameTimer?.cancel();
    _mapController?.dispose();
    _itemsSub?.cancel();
    _playerItemsSub?.cancel();
    _playerDocSub?.cancel();
    _taggerLocationsSub?.cancel();
    _trapsSub?.cancel();
    _taggerMarkerTimer?.cancel();
    _runnerMarkerTimer?.cancel();
    _positionSub?.cancel();
    _trapReleaseTimer?.cancel();
    _trapCountdownTimer?.cancel();
    _freezeReleaseTimer?.cancel();
    _freezeCountdownTimer?.cancel();
    super.dispose();
  }

  bool _isPointInAnyField(LatLng point) {
    if (_fieldPolygons.isEmpty) return false;
    for (final poly in _fieldPolygons) {
      final pts = poly.points.toList();
      if (_pointInPolygon(point, pts)) return true;
    }
    return false;
  }

  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude, yi = polygon[i].latitude;
      final xj = polygon[j].longitude, yj = polygon[j].latitude;

      final intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi + 0.0) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  PartyMemberRole _resolveRole() {
    final members = widget.args.lobby.allMembers;
    final me = members.firstWhere(
      (m) => m.userId == widget.args.currentUserId,
    );
    return me.role;
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_countdown > 1) {
        setState(() => _countdown -= 1);
        return;
      }
      timer.cancel();
      setState(() {
        _countdown = 0;
        _showGo = true;
      });
      _startGameTimer();
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() => _showGo = false);
        }
      });
    });
  }

  void _startGameTimer() {
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _remainingSeconds = (_remainingSeconds - 1).clamp(0, 99999);
      });
      if (_remainingSeconds == 0) {
        timer.cancel();
      }
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
        _updatePlayerMarker(latLng);
      });
      _startLiveLocationTracking(latLng);

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, 17),
      );
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
        _fieldPolygons = {
          Polygon(
            polygonId: const PolygonId('field'),
            points: polygon,
            fillColor: _palette.accent.withOpacity(0.12),
            strokeColor: _palette.accent,
            strokeWidth: 2,
          ),
        };
        // after loading the polygon, if we already have visible items, ensure markers
        if (_visibleItems.isNotEmpty) {
          _refreshItemMarkers();
        }
      });
    } catch (e, s) {
      debugPrint('Failed to load field polygon: $e\n$s');
    }
  }

  void _goHome() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.home,
      (route) => false,
    );
  }

  void _subscribeToGameItems(String gameId) {
    final typesToShow = _role == PartyMemberRole.runner
        ? const {'FAKE_LOCATION', 'FREEZE_TAGGER', 'SEE_TAGGER'}
        : const {'TRAP', 'FAKE_LOCATION_TAGGER', 'SEE_RUNNER'};
    if (typesToShow.isEmpty) return;

    _itemsSub = _partyService.watchGameItems(gameId).listen((items) {
      final Map<String, GameItem> picked = {};
      for (final it in items) {
        if (typesToShow.contains(it.type) && it.state == 'AVAILABLE') {
          picked.putIfAbsent(it.type, () => it);
        }
      }

      if (!mounted) return;
      setState(() {
        _visibleItems
          ..clear()
          ..addAll(picked);

        _refreshItemMarkers();
      });
    });
  }

  Future<void> _fetchPlayerId(String gameId) async {
    try {
      final playerId =
          await _partyService.findPlayerIdByUser(gameId, widget.args.currentUserId);
      if (!mounted) return;
      setState(() {
        _playerId = playerId;
      });
      if (playerId != null) {
        _subscribeToPlayerItems(gameId, playerId);
        _subscribeToPlayerDoc(gameId, playerId);
      }
    } catch (e, s) {
      debugPrint('Failed to fetch playerId: $e\n$s');
      if (mounted) {
        _showSnack('プレイヤー情報の取得に失敗しました');
      }
    }
  }

  Future<String?> _ensurePlayerId() async {
    if (_playerId != null) return _playerId;
    final gameId = widget.args.gameId;
    if (gameId == null) return null;
    await _fetchPlayerId(gameId);
    if (_playerId == null) {
      _showSnack('プレイヤー情報が見つかりません');
    }
    return _playerId;
  }

  void _subscribeToPlayerItems(String gameId, String playerId) {
    _playerItemsSub?.cancel();
    _playerItemsSub = _partyService.watchPlayerItems(gameId, playerId).listen((items) {
      if (!mounted) return;
      setState(() {
        _playerItems = items;
      });
    });
  }

  void _subscribeToPlayerDoc(String gameId, String playerId) {
    _playerDocSub?.cancel();
    _playerDocSub = _partyService.watchPlayerDoc(gameId, playerId).listen((snap) {
      final data = snap.data();
      if (!mounted || data == null) return;
      if (_role == PartyMemberRole.tagger) {
        final cooldowns = data['cooldowns'] as Map<String, dynamic>?;
        _handleFreezeCooldown(cooldowns);
      }
    });
  }

  void _subscribeToTaggerLocations(String gameId) {
    _taggerLocationsSub?.cancel();
    _taggerLocationsSub = _partyService.watchTaggerLocations(gameId).listen((locations) {
      if (!mounted) return;
      setState(() {
        _taggerLocations = locations;
      });
    });
  }

  void _subscribeToTraps(String gameId) {
    _trapsSub?.cancel();
    _trapsSub = _partyService.watchTraps(gameId).listen((traps) {
      if (!mounted) return;
      setState(() {
        _traps
          ..clear()
          ..addEntries(traps.map((t) => MapEntry(t.trapId, t)));
        _refreshTrapMarkers();
      });
    });
  }

  void _refreshItemMarkers() {
    _markers.removeWhere((m) => m.markerId.value.startsWith('item_'));
    for (final it in _visibleItems.values) {
      final pos = LatLng(it.lat, it.lng);
      if (!_isPointInAnyField(pos)) continue;
      _markers.add(
        Marker(
          markerId: MarkerId('item_${it.itemId}'),
          position: pos,
          infoWindow: InfoWindow(title: it.type),
          icon: BitmapDescriptor.defaultMarkerWithHue(_itemHue(it.type)),
          onTap: null,
        ),
      );
    }
  }

  void _refreshTrapMarkers() {
    _markers.removeWhere((m) => m.markerId.value.startsWith('trap_'));
    if (_role != PartyMemberRole.tagger) return;
    for (final trap in _traps.values) {
      if (trap.state != 'ACTIVE') continue;
      final pos = LatLng(trap.lat, trap.lng);
      _markers.add(
        Marker(
          markerId: MarkerId('trap_${trap.trapId}'),
          position: pos,
          infoWindow: const InfoWindow(title: '罠'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
        ),
      );
    }
  }

  void _handleItemChipTap(PlayerItem item) {
    if (_isUsingSeeTagger) return;
    if (_isFreezingTagger) return;
    switch (item.type) {
      case 'FAKE_LOCATION':
        _showSnack('FAKE_LOCATION は自動で発動します');
        break;
      case 'SEE_TAGGER':
        _useSeeTagger(item);
        break;
      case 'FREEZE_TAGGER':
        _useFreezeTagger(item);
        break;
      default:
        _showSnack('このアイテムの使用はまだできません');
    }
  }

  void _handleTaggerItemChipTap(PlayerItem item) {
    if (_isPlacingTrap) return;
    switch (item.type) {
      case 'TRAP':
        _useTrap(item);
        break;
      default:
        _showSnack('このアイテムの使用はまだできません');
    }
  }

  Future<void> _useSeeTagger(PlayerItem item) async {
    if (_isUsingSeeTagger) return;
    final gameId = widget.args.gameId;
    if (gameId == null) {
      _showSnack('ゲーム情報が見つかりません');
      return;
    }

    final playerId = await _ensurePlayerId();
    if (playerId == null) return;

    setState(() => _isUsingSeeTagger = true);
    try {
      final locations = await _partyService.fetchTaggerLocations(gameId);
      if (!mounted) return;
      final markerList = <Marker>[];
      for (final loc in locations) {
        final pos = loc.latLng;
        if (pos == null) continue;
        markerList.add(
          Marker(
            markerId: MarkerId('tagger_${loc.playerId}'),
            position: pos,
            infoWindow: const InfoWindow(title: '鬼の位置'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        );
      }

      if (markerList.isEmpty) {
        _showSnack('鬼の位置情報がありません');
      } else {
        setState(() {
          _markers.removeWhere((m) => m.markerId.value.startsWith('tagger_'));
          _markers.addAll(markerList);
        });
        _taggerMarkerTimer?.cancel();
        _taggerMarkerTimer = Timer(const Duration(seconds: 3), () {
          if (!mounted) return;
          setState(() {
            _markers.removeWhere((m) => m.markerId.value.startsWith('tagger_'));
          });
        });
        _showSnack('鬼の位置を表示中');
      }

      final consumed = await _partyService.consumePlayerItem(
        gameId: gameId,
        playerId: playerId,
        itemId: item.itemId,
      );
      if (!consumed && mounted) {
        _showSnack('アイテムの消費に失敗しました');
      }
    } catch (e, s) {
      debugPrint('Failed to use SEE_TAGGER: $e\n$s');
      if (mounted) {
        _showSnack('鬼の位置を取得できませんでした');
      }
    } finally {
      if (mounted) {
        setState(() => _isUsingSeeTagger = false);
      }
    }
  }

  Future<void> _useFreezeTagger(PlayerItem item) async {
    if (_isFreezingTagger) return;
    final gameId = widget.args.gameId;
    if (gameId == null) {
      _showSnack('ゲーム情報が見つかりません');
      return;
    }
    final playerId = await _ensurePlayerId();
    if (playerId == null) return;
    final current = _currentLatLng;
    if (current == null) {
      _showSnack('現在位置を取得できていません');
      return;
    }
    if (!_isPointInAnyField(current)) {
      _showSnack('フィールド内でのみ設置できます');
      return;
    }
    final target = _findNearestTaggerWithinMeters(current, 5);
    if (target == null) {
      _showSnack('半径5m以内に鬼がいません');
      return;
    }

    setState(() => _isFreezingTagger = true);
    try {
      final success = await _partyService.freezeTagger(
        gameId: gameId,
        targetPlayerId: target.playerId,
        runnerPlayerId: playerId,
      );
      if (!mounted) return;
      if (!success) {
        _showSnack('鬼を停止させられませんでした');
      } else {
        final consumed = await _partyService.consumePlayerItem(
          gameId: gameId,
          playerId: playerId,
          itemId: item.itemId,
        );
        if (!consumed) {
          _showSnack('アイテムの消費に失敗しました');
        } else {
          _showSnack('鬼を5秒間停止させました');
        }
      }
    } catch (e, s) {
      debugPrint('Failed to use FREEZE_TAGGER: $e\n$s');
      if (mounted) {
        _showSnack('鬼を停止させられませんでした');
      }
    } finally {
      if (mounted) {
        setState(() => _isFreezingTagger = false);
      }
    }
  }

  Future<void> _useTrap(PlayerItem item) async {
    if (_isPlacingTrap) return;
    final gameId = widget.args.gameId;
    if (gameId == null) {
      _showSnack('ゲーム情報が見つかりません');
      return;
    }
    final playerId = await _ensurePlayerId();
    if (playerId == null) return;
    final current = _currentLatLng;
    if (current == null) {
      _showSnack('現在位置を取得できていません');
      return;
    }
    setState(() => _isPlacingTrap = true);
    try {
      final placed = await _partyService.placeTrap(
        gameId: gameId,
        playerId: playerId,
        lat: current.latitude,
        lng: current.longitude,
      );
      if (!mounted) return;
      if (!placed) {
        _showSnack('トラップの設置に失敗しました');
        return;
      }
      final consumed = await _partyService.consumePlayerItem(
        gameId: gameId,
        playerId: playerId,
        itemId: item.itemId,
      );
      if (!consumed) {
        _showSnack('アイテムの消費に失敗しました');
      } else {
        _showSnack('トラップを設置しました');
      }
    } catch (e, s) {
      debugPrint('Failed to place trap: $e\n$s');
      if (mounted) {
        _showSnack('トラップの設置に失敗しました');
      }
    } finally {
      if (mounted) {
        setState(() => _isPlacingTrap = false);
      } else {
        _isPlacingTrap = false;
      }
    }
  }

  PlayerLocation? _findNearestTaggerWithinMeters(LatLng origin, double radiusMeters) {
    PlayerLocation? closest;
    var minDistance = double.infinity;
    for (final loc in _taggerLocations) {
      final pos = loc.latLng;
      if (pos == null) continue;
      final dist = Geolocator.distanceBetween(
        origin.latitude,
        origin.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (dist <= radiusMeters && dist < minDistance) {
        minDistance = dist;
        closest = loc;
      }
    }
    return closest;
  }

  void _checkTrapCollision(LatLng latLng) {
    if (_isTrapped) return;
    GameTrap? hitTrap;
    for (final trap in _traps.values) {
      if (trap.state != 'ACTIVE') continue;
      final dist = Geolocator.distanceBetween(
        latLng.latitude,
        latLng.longitude,
        trap.lat,
        trap.lng,
      );
      if (dist <= 5) {
        hitTrap = trap;
        break;
      }
    }
    if (hitTrap != null) {
      unawaited(_onTrapTriggered(hitTrap, latLng));
    }
  }

  void _enforceTrapRestriction(LatLng latLng) {
    if (!_isTrapped || _trapOrigin == null) return;
    final dist = Geolocator.distanceBetween(
      _trapOrigin!.latitude,
      _trapOrigin!.longitude,
      latLng.latitude,
      latLng.longitude,
    );
    if (dist > 5 && !_trapMovementDialogVisible) {
      _showTrapMovementWarning();
    }
  }

  Future<void> _onTrapTriggered(GameTrap trap, LatLng latLng) async {
    final gameId = widget.args.gameId;
    final playerId = await _ensurePlayerId();
    if (gameId == null || playerId == null) return;
    final success = await _partyService.triggerTrap(
      gameId: gameId,
      trapId: trap.trapId,
      runnerPlayerId: playerId,
    );
    if (!success || !mounted) return;
    setState(() {
      _isTrapped = true;
      _trapOrigin = latLng;
      _trapRemainingSeconds = 5;
    });
    _trapCountdownTimer?.cancel();
    _trapCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _trapRemainingSeconds = (_trapRemainingSeconds - 1).clamp(0, 5);
      });
      if (_trapRemainingSeconds <= 0) {
        timer.cancel();
      }
    });
    _trapReleaseTimer?.cancel();
    _trapReleaseTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        _isTrapped = false;
        _trapOrigin = null;
        _trapRemainingSeconds = 0;
      });
      _trapMovementDialogVisible = false;
    });
    _showTrapCaptureDialog();
  }

  Future<void> _showTrapCaptureDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('トラップ発動'),
        content: const Text('トラップにかかりました。5秒間その場で待機してください。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTrapMovementWarning() async {
    if (!mounted || _trapMovementDialogVisible) return;
    _trapMovementDialogVisible = true;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('動けません'),
        content: const Text('まだ自由に動けません。指定範囲内で待機してください。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) {
      setState(() {
        _trapMovementDialogVisible = false;
      });
    } else {
      _trapMovementDialogVisible = false;
    }
  }

  void _handleFreezeCooldown(Map<String, dynamic>? cooldowns) {
    final raw = cooldowns?['freezeTaggerUntil'];
    Timestamp? freezeUntil;
    if (raw is Timestamp) {
      freezeUntil = raw;
    }
    if (freezeUntil == null) {
      _stopFreezeState();
      return;
    }
    final remaining = freezeUntil.toDate().difference(DateTime.now()).inSeconds;
    if (remaining > 0) {
      _startFreezeState(remaining);
    } else {
      _stopFreezeState();
    }
  }

  void _startFreezeState(int remainingSeconds) {
    final seconds = remainingSeconds.clamp(1, 30);
    _freezeCountdownTimer?.cancel();
    _freezeReleaseTimer?.cancel();
    setState(() {
      _isFrozen = true;
      _freezeOrigin ??= _currentLatLng;
      _freezeRemainingSeconds = seconds;
    });
    _freezeCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _freezeRemainingSeconds = (_freezeRemainingSeconds - 1).clamp(0, 30);
      });
      if (_freezeRemainingSeconds <= 0) {
        timer.cancel();
      }
    });
    _freezeReleaseTimer = Timer(Duration(seconds: seconds), () {
      _stopFreezeState();
    });
    if (!_freezeDialogVisible) {
      _freezeDialogVisible = true;
      unawaited(_showFreezeDialog());
    }
  }

  void _stopFreezeState() {
    if (!_isFrozen) return;
    _freezeCountdownTimer?.cancel();
    _freezeReleaseTimer?.cancel();
    if (mounted) {
      setState(() {
        _isFrozen = false;
        _freezeOrigin = null;
        _freezeRemainingSeconds = 0;
      });
    } else {
      _isFrozen = false;
      _freezeOrigin = null;
      _freezeRemainingSeconds = 0;
    }
    _freezeMovementDialogVisible = false;
    _freezeDialogVisible = false;
  }

  void _enforceFreezeRestriction(LatLng latLng) {
    if (!_isFrozen || _freezeOrigin == null) return;
    final dist = Geolocator.distanceBetween(
      _freezeOrigin!.latitude,
      _freezeOrigin!.longitude,
      latLng.latitude,
      latLng.longitude,
    );
    if (dist > 5 && !_freezeMovementDialogVisible) {
      _freezeMovementDialogVisible = true;
      unawaited(_showFreezeMovementWarning());
    }
  }

  Future<void> _showFreezeDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('凍結中'),
        content: const Text('鬼は5秒間動けません。範囲内で待機してください。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) {
      setState(() {
        _freezeDialogVisible = false;
      });
    } else {
      _freezeDialogVisible = false;
    }
  }

  Future<void> _showFreezeMovementWarning() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('まだ動けません'),
        content: const Text('凍結が解除されるまで指定範囲内で待機してください。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) {
      setState(() {
        _freezeMovementDialogVisible = false;
      });
    } else {
      _freezeMovementDialogVisible = false;
    }
  }

  bool _isItemUsable(PlayerItem item) {
    if (item.type != 'FREEZE_TAGGER') {
      return true;
    }
    final current = _currentLatLng;
    if (current == null) return false;
    final target = _findNearestTaggerWithinMeters(current, 5);
    return target != null;
  }

  bool _isTaggerItemUsable(PlayerItem item) {
    if (item.type == 'TRAP') {
      return _currentLatLng != null && !_isPlacingTrap && !_isFrozen;
    }
    return true;
  }

  double _itemHue(String type) {
    switch (type) {
      case 'FAKE_LOCATION':
        return BitmapDescriptor.hueAzure;
      case 'SEE_TAGGER':
        return BitmapDescriptor.hueGreen;
      case 'FREEZE_TAGGER':
        return BitmapDescriptor.hueViolet;
      case 'TRAP':
        return BitmapDescriptor.hueRed;
      case 'FAKE_LOCATION_TAGGER':
        return BitmapDescriptor.hueOrange;
      case 'SEE_RUNNER':
        return BitmapDescriptor.hueBlue;
      default:
        return BitmapDescriptor.hueAzure;
    }
  }

  Future<void> _onItemMarkerTapped(GameItem item) async {
    if (_isPickingItem) return;
    final gameId = widget.args.gameId;
    if (gameId == null) return;
    final playerId = await _ensurePlayerId();
    if (playerId == null) return;

    setState(() => _isPickingItem = true);
    final success = await _partyService.pickupItem(
      gameId: gameId,
      itemId: item.itemId,
      playerId: playerId,
    );
    if (!mounted) return;
    setState(() => _isPickingItem = false);

    if (success) {
      _showSnack('${item.type} を取得しました');
    } else {
      _showSnack('アイテム取得に失敗しました');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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

    final statsWidget = _StatsBar(
      accent: _palette.accent,
      capturedCount: _capturedCount,
      remainingPlayers: remainingPlayers,
      items: _playerItems,
      onItemTap: _role == PartyMemberRole.runner
          ? _handleItemChipTap
          : (_role == PartyMemberRole.tagger ? _handleTaggerItemChipTap : null),
      onItemEnabled: _role == PartyMemberRole.runner
          ? _isItemUsable
          : (_role == PartyMemberRole.tagger ? _isTaggerItemUsable : null),
    );

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
                    if (_role == PartyMemberRole.runner && _isTrapped)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _StatusOverlay(
                          accent: _palette.accent,
                          icon: Icons.warning_amber_rounded,
                          title: 'トラップ発動中',
                          message: 'あと ${_trapRemainingSeconds}s 待機してください',
                        ),
                      ),
                    if (_role == PartyMemberRole.tagger && _isFrozen)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _StatusOverlay(
                          accent: _palette.accent,
                          icon: Icons.ac_unit,
                          title: '凍結中',
                          message: _freezeRemainingSeconds > 0
                              ? 'あと ${_freezeRemainingSeconds}s 待機してください'
                              : '解除されるまで待機してください',
                        ),
                      ),
                    if (_role == PartyMemberRole.tagger) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _AbilityGaugeButton(
                            accent: _palette.accent,
                            percent: _gaugePercent,
                            isReady: _gaugePercent >= 100,
                            onActivate: _activateTaggerAbility,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: statsWidget),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _CatchButton(
                        accent: _palette.accent,
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('捕まえ処理は未実装です')),
                          );
                        },
                      ),
                    ] else
                      statsWidget,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startLiveLocationTracking(LatLng initial) {
    if (_positionSub != null) return;
    if (_role == PartyMemberRole.tagger) {
      _lastGaugeLatLng ??= initial;
    }
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 2,
      ),
    ).listen((position) {
      _handlePositionUpdate(position);
    });
  }

  void _handlePositionUpdate(Position position) {
    final latLng = LatLng(position.latitude, position.longitude);
    if (_role == PartyMemberRole.tagger) {
      _handleTaggerMovement(latLng);
      _enforceFreezeRestriction(latLng);
    } else {
      setState(() {
        _currentLatLng = latLng;
        _updatePlayerMarker(latLng);
      });
    }
    if (_role == PartyMemberRole.runner) {
      _checkTrapCollision(latLng);
      _enforceTrapRestriction(latLng);
    }
  }

  void _handleTaggerMovement(LatLng latLng) {
    final prev = _lastGaugeLatLng;
    _lastGaugeLatLng = latLng;
    var gainedPercent = 0;
    if (prev != null) {
      final delta = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        latLng.latitude,
        latLng.longitude,
      );
      _gaugeDistanceBuffer += delta;
      while (_gaugeDistanceBuffer >= 5) {
        _gaugeDistanceBuffer -= 5;
        gainedPercent += 1;
      }
    }
    if (!mounted) return;
    setState(() {
      _currentLatLng = latLng;
      _updatePlayerMarker(latLng);
      if (gainedPercent > 0 && _gaugePercent < 100) {
        _gaugePercent = (_gaugePercent + gainedPercent).clamp(0, 100);
      }
    });
  }

  void _activateTaggerAbility() {
    if (_gaugePercent < 100) {
      _showSnack('ゲージが満タンになるまで歩いてください');
      return;
    }
    if (_isFrozen) {
      _showSnack('凍結中は使用できません');
      return;
    }
    if (_isUsingTaggerAbility) return;
    unawaited(_executeTaggerAbility());
  }

  Future<void> _executeTaggerAbility() async {
    final gameId = widget.args.gameId;
    if (gameId == null) {
      _showSnack('ゲーム情報が見つかりません');
      return;
    }
    setState(() {
      _isUsingTaggerAbility = true;
      _gaugePercent = 0;
      _gaugeDistanceBuffer = 0;
    });
    try {
      final locations = await _partyService.fetchRunnerLocationsForTagger(gameId);
      if (!mounted) return;
      final markers = <Marker>[];
      for (final loc in locations) {
        final pos = loc.latLng;
        if (pos == null) continue;
        markers.add(
          Marker(
            markerId: MarkerId('runner_${loc.playerId}_${loc.isDecoy ? 'decoy' : 'real'}'),
            position: pos,
            infoWindow: InfoWindow(title: loc.isDecoy ? '偽の位置' : '逃走者'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              loc.isDecoy ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueGreen,
            ),
          ),
        );
      }
      if (markers.isEmpty) {
        _showSnack('逃走者の位置情報がありません');
      } else {
        setState(() {
          _markers.removeWhere((m) => m.markerId.value.startsWith('runner_'));
          _markers.addAll(markers);
        });
        _runnerMarkerTimer?.cancel();
        _runnerMarkerTimer = Timer(const Duration(seconds: 5), () {
          if (!mounted) return;
          setState(() {
            _markers.removeWhere((m) => m.markerId.value.startsWith('runner_'));
          });
        });
        _showSnack('逃走者の位置を表示中');
      }
    } catch (e, s) {
      debugPrint('Failed to activate tagger ability: $e\n$s');
      if (mounted) {
        _showSnack('逃走者の位置を取得できませんでした');
      }
    } finally {
      if (mounted) {
        setState(() => _isUsingTaggerAbility = false);
      } else {
        _isUsingTaggerAbility = false;
      }
    }
  }

  void _updatePlayerMarker(LatLng latLng) {
    _markers.removeWhere((m) => m.markerId.value == 'me');
    _markers.add(
      Marker(
        markerId: const MarkerId('me'),
        position: latLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueAzure,
        ),
      ),
    );
  }
}

class _CatchButton extends StatelessWidget {
  final Color accent;
  final VoidCallback onPressed;

  const _CatchButton({
    required this.accent,
    required this.onPressed,
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
        onPressed: onPressed,
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
  final List<PlayerItem> items;
  final ValueChanged<PlayerItem>? onItemTap;
  final bool Function(PlayerItem item)? onItemEnabled;

  const _StatsBar({
    required this.accent,
    required this.capturedCount,
    required this.remainingPlayers,
    required this.items,
    this.onItemTap,
    this.onItemEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final hasItems = items.isNotEmpty;

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
                '所持アイテム',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text('${items.length}個', style: const TextStyle(color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasItems)
            const Text(
              'まだアイテムはありません',
              style: TextStyle(color: Colors.black54),
            )
          else
            _ItemInventoryList(
              accent: accent,
              items: items,
              onItemTap: onItemTap,
              onItemEnabled: onItemEnabled,
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

class _ItemInventoryList extends StatelessWidget {
  final Color accent;
  final List<PlayerItem> items;
  final ValueChanged<PlayerItem>? onItemTap;
  final bool Function(PlayerItem item)? onItemEnabled;

  const _ItemInventoryList({
    required this.accent,
    required this.items,
    this.onItemTap,
    this.onItemEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final double listHeight =
        (items.length * 52.0).clamp(64.0, 200.0) as double;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: accent.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Scrollbar(
        thumbVisibility: items.length > 3,
        child: SizedBox(
          height: listHeight,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            physics: items.length > 3
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final enabled = onItemEnabled?.call(item) ?? true;
              final label = item.count > 1 ? '${item.type} x${item.count}' : item.type;
              return ListTile(
                dense: true,
                enabled: enabled,
                leading: Icon(Icons.inventory_2, color: accent),
                title: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: (onItemTap != null && enabled) ? () => onItemTap?.call(item) : null,
                trailing: onItemTap != null
                    ? Icon(
                        Icons.play_circle,
                        color: enabled ? accent : Colors.black26,
                      )
                    : null,
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 1),
          ),
        ),
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

class _AbilityGaugeButton extends StatelessWidget {
  final double percent;
  final bool isReady;
  final Color accent;
  final VoidCallback onActivate;

  const _AbilityGaugeButton({
    required this.percent,
    required this.isReady,
    required this.accent,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    final displayPercent = percent.clamp(0, 100).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'リッスンゲージ',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 90,
          height: 90,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 90,
                height: 90,
                child: CircularProgressIndicator(
                  value: percent.clamp(0, 100) / 100,
                  strokeWidth: 6,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
              SizedBox(
                width: 70,
                height: 70,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: isReady ? accent : Colors.grey.shade500,
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: isReady ? onActivate : null,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.radar, color: Colors.white, size: 20),
                      const SizedBox(height: 2),
                      Text(
                        '$displayPercent%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          isReady ? '発動可能' : '5m移動で +1%',
          style: TextStyle(
            color: isReady ? accent : Colors.black54,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StatusOverlay extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color accent;

  const _StatusOverlay({
    required this.title,
    required this.message,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
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
