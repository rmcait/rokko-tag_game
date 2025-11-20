import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tag_game/core/constants/app_constants.dart';
import 'package:tag_game/data/models/item_model.dart';
import 'package:tag_game/data/services/item_service.dart';
import 'package:tag_game/data/services/party_service.dart';

class MockPlayPage extends StatefulWidget {
  final String partyId;
  final String gameId;
  final String currentUserId;
  final String role; // 'RUNNER' or 'TAGGER' (default RUNNER)
  /// Optional stream that emits `true` when an external service detects
  /// that a tagger is within the 5m freeze radius of this runner.
  final Stream<bool>? taggerProximityStream;
  final bool initialTaggerWithinRange;

  const MockPlayPage({
    super.key,
    required this.partyId,
    required this.gameId,
    required this.currentUserId,
    this.role = 'RUNNER',
    this.taggerProximityStream,
    this.initialTaggerWithinRange = false,
  });

  @override
  State<MockPlayPage> createState() => _MockPlayPageState();
}

class _MockPlayPageState extends State<MockPlayPage> {
  GoogleMapController? _mapController;
  LatLng _position = const LatLng(35.0, 135.0);
  final ItemService _itemService = ItemService();
  final PartyService _partyService = PartyService();
  List<ItemModel> _items = [];
  final Map<String, int> _inventory = {}; // itemTypeCode -> count
  // SEE_TAGGER support
  DateTime? _seeExpiresAt;
  Set<Marker> _seeMarkers = {};
  bool _statusReset = false;
  bool _isResettingStatus = false;
  bool _taggerWithinRange = false;
  bool _isFreezingTagger = false;

  // Runner max inventory
  static const int _runnerMaxItems = 2;

  // small move step in meters
  static const double _moveStepMeters = 4.5; // ~4.5m per press

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _taggerWithinRange = widget.initialTaggerWithinRange;
    _subscribeItems();
    _subscribeProximity();
  }

  StreamSubscription<List<ItemModel>>? _itemsSub;
  StreamSubscription<bool>? _proximitySub;

  void _subscribeItems() {
    setState(() => _loading = true);
    _itemsSub = _itemService
        .watchItemsForGame(widget.gameId,
            visibility: widget.role == 'TAGGER' ? 'TAGGER' : 'RUNNER')
        .listen((items) {
      setState(() {
        _items = items;
        if (_position.latitude == 35.0 && items.isNotEmpty) {
          // only re-center initially if default position
          _position = LatLng(items.first.lat, items.first.lng);
        }
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _itemsSub?.cancel();
    _proximitySub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _mapController?.moveCamera(CameraUpdate.newLatLngZoom(_position, 16));
  }

  void _moveByMeters({required double eastMeters, required double northMeters}) {
    final newPos = _offsetLatLng(_position, eastMeters, northMeters);
    setState(() {
      _position = newPos;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(_position));
    _tryPickupNearbyItems();
  }

  LatLng _offsetLatLng(LatLng from, double eastMeters, double northMeters) {
    // Approx convert meters to degrees
    final lat = from.latitude + (northMeters / 111320.0);
    final lng = from.longitude + (eastMeters / (111320.0 * cos(from.latitude * pi / 180)));
    return LatLng(lat, lng);
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final A = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    final C = 2 * atan2(sqrt(A), sqrt(1 - A));
    return r * C;
  }

  double _deg2rad(double d) => d * (pi / 180.0);

  void _subscribeProximity() {
    _proximitySub = widget.taggerProximityStream?.listen((value) {
      if (!mounted) return;
      setState(() {
        _taggerWithinRange = value;
      });
    });
  }

  void _tryPickupNearbyItems() {
    if (widget.role != 'RUNNER') return; // pickup only for runners in this mock

    final pickupRadius = AppConstants.itemFreezeRadiusMeters; // reuse constant for proximity
    for (final item in List<ItemModel>.from(_items)) {
      final itemPos = LatLng(item.lat, item.lng);
      final d = _distanceMeters(_position, itemPos);
      if (d <= pickupRadius) {
        _attemptPickup(item);
      }
    }
  }

  Future<void> _attemptPickup(ItemModel item) async {
    final currentCount = _inventory[item.type.code] ?? 0;
    if (currentCount >= _runnerMaxItems) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('アイテムは最大$_runnerMaxItems個までしか持てません')),
      );
      return;
    }

    final success = await _itemService.pickItem(
      gameId: widget.gameId,
      itemId: item.itemId,
      pickerPlayerId: widget.currentUserId,
      runnerMaxItems: _runnerMaxItems,
    );

    if (success) {
      setState(() {
        _inventory[item.type.code] = currentCount + 1;
        _items.removeWhere((it) => it.itemId == item.itemId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.currentUserId} さんが ${item.type.code} を獲得しました！')),
      );
    }
  }

  Widget _buildInventory() {
    final entries = _inventory.entries.toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: entries.isEmpty
              ? [const Text('在庫: なし')]
              : entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _iconForItemCode(e.key),
                        const SizedBox(height: 4),
                        Text('x${e.value}'),
                      ],
                    ),
                  )).toList(),
        ),
      ),
    );
  }

  Future<void> _activateSeeTagger() async {
    if ((_inventory['SEE_TAGGER'] ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SEE_TAGGER がありません')));
      return;
    }

    final positions = await _itemService.useSeeTagger(gameId: widget.gameId, byPlayerId: widget.currentUserId);
    if (positions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('タグ情報を取得できませんでした')));
      return;
    }

    // show markers for duration
    final List<Marker> newMarkers = [];
    for (final p in positions) {
      final mid = MarkerId('see_${p['playerId']}');
      final lat = (p['lat'] as num).toDouble();
      final lng = (p['lng'] as num).toDouble();
      newMarkers.add(Marker(markerId: mid, position: LatLng(lat, lng), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan), infoWindow: InfoWindow(title: 'Tagger ${p['playerId']}')));
    }

    setState(() {
      _seeMarkers = newMarkers.toSet();
      _seeExpiresAt = DateTime.now().toUtc().add(Duration(seconds: AppConstants.itemSeeTaggerDurationSeconds));
      // decrement local inventory if present (server transaction already decremented)
      final cur = _inventory['SEE_TAGGER'] ?? 0;
      if (cur > 0) _inventory['SEE_TAGGER'] = cur - 1;
    });

    Future.delayed(Duration(seconds: AppConstants.itemSeeTaggerDurationSeconds), () {
      if (mounted) {
        setState(() {
          _seeMarkers = {};
          _seeExpiresAt = null;
        });
      }
    });
  }

  Widget _iconForItemCode(String code) {
    IconData icon;
    switch (code) {
      case 'FREEZE_TAGGER':
        icon = Icons.ac_unit;
        break;
      case 'SEE_TAGGER':
        icon = Icons.visibility;
        break;
      case 'FAKE_LOCATION':
        icon = Icons.location_off;
        break;
      case 'TRAP':
        icon = Icons.warning;
        break;
      case 'FREEZE_ALL':
        icon = Icons.stop_circle;
        break;
      default:
        icon = Icons.circle;
    }
    return Icon(icon);
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('me'),
        position: _position,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(title: widget.currentUserId),
      ),
    };

    for (final item in _items) {
      markers.add(Marker(
        markerId: MarkerId(item.itemId),
        position: LatLng(item.lat, item.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(title: item.type.code),
      ));
    }

    // include SEE markers if active
    markers.addAll(_seeMarkers);

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _resetPartyStatusIfNeeded();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mock Play - 仮プレイ画面'),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition:
                    CameraPosition(target: _position, zoom: 16),
                markers: _buildMarkers(),
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
              ),
              Positioned(
                right: 12,
                top: 12,
                child: _buildInventory(),
              ),
              // SEE button
              Positioned(
                left: 12,
                top: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_seeExpiresAt != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                              'SEE expires in ${_seeExpiresAt!.difference(DateTime.now().toUtc()).inSeconds}s'),
                        ),
                      ),
                    if (widget.role == 'RUNNER')
                      ElevatedButton.icon(
                        onPressed: (_inventory['SEE_TAGGER'] ?? 0) > 0
                            ? _activateSeeTagger
                            : null,
                        icon: const Icon(Icons.visibility),
                        label: const Text('See Tagger'),
                      ),
                    if (widget.role == 'RUNNER')
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: ElevatedButton.icon(
                          onPressed: _canUseFreezeTagger() ? _useFreezeTagger : null,
                          icon: const Icon(Icons.ac_unit),
                          label: const Text('Freeze Tagger'),
                        ),
                      ),
                    if (widget.role == 'RUNNER')
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          _taggerWithinRange
                              ? '鬼が近くにいます！'
                              : '鬼が5m以内に来ると使用可能',
                          style: TextStyle(
                            color: _taggerWithinRange ? Colors.red : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    if (widget.role == 'RUNNER' && _hasFakeLocationItem())
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          '偽の位置共有アイテム保持中（鬼が位置可視化を使うと自動で発動）',
                          style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              // D-pad centered bottom
              Positioned(
                bottom: 48,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 160,
                    height: 160,
                    child: Stack(
                      children: [
                        // Up
                        Align(
                          alignment: const Alignment(0, -0.8),
                          child: _dpadButton('dpad_up', Icons.arrow_upward, () {
                            _moveByMeters(
                                eastMeters: 0, northMeters: _moveStepMeters);
                          }),
                        ),
                        // Down
                        Align(
                          alignment: const Alignment(0, 0.8),
                          child:
                              _dpadButton('dpad_down', Icons.arrow_downward,
                                  () {
                            _moveByMeters(
                                eastMeters: 0, northMeters: -_moveStepMeters);
                          }),
                        ),
                        // Left
                        Align(
                          alignment: const Alignment(-0.8, 0),
                          child: _dpadButton('dpad_left', Icons.arrow_back, () {
                            _moveByMeters(
                                eastMeters: -_moveStepMeters, northMeters: 0);
                          }),
                        ),
                        // Right
                        Align(
                          alignment: const Alignment(0.8, 0),
                          child:
                              _dpadButton('dpad_right', Icons.arrow_forward,
                                  () {
                            _moveByMeters(
                                eastMeters: _moveStepMeters, northMeters: 0);
                          }),
                        ),
                        // Center
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black26, blurRadius: 4),
                              ],
                            ),
                            child: const Center(child: Icon(Icons.my_location)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Loading overlay
              if (_loading) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dpadButton(String tag, IconData icon, VoidCallback onPressed) {
    return SizedBox(
      width: 56,
      height: 56,
      child: FloatingActionButton.small(
        heroTag: tag,
        onPressed: onPressed,
        child: Icon(icon),
      ),
    );
  }

  Future<void> _resetPartyStatusIfNeeded() async {
    if (_statusReset || _isResettingStatus) return;
    _isResettingStatus = true;
    try {
      await _partyService.resetPartyToWaiting(widget.partyId);
      _statusReset = true;
    } catch (e) {
      debugPrint('Failed to reset party status: $e');
    } finally {
      _isResettingStatus = false;
    }
  }

  bool _canUseFreezeTagger() {
    if (widget.role != 'RUNNER') return false;
    final available = (_inventory['FREEZE_TAGGER'] ?? 0) > 0;
    return available && _taggerWithinRange && !_isFreezingTagger;
  }

  bool _hasFakeLocationItem() =>
      (_inventory['FAKE_LOCATION'] ?? 0) > 0;

  Future<void> _useFreezeTagger() async {
    if (!_canUseFreezeTagger()) return;
    setState(() {
      _isFreezingTagger = true;
    });
    try {
      final success = await _itemService.useFreezeTagger(
        gameId: widget.gameId,
        byPlayerId: widget.currentUserId,
        position: _position,
      );
      if (!mounted) return;
      if (success) {
        final cur = _inventory['FREEZE_TAGGER'] ?? 0;
        if (cur > 0) {
          setState(() {
            _inventory['FREEZE_TAGGER'] = cur - 1;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('鬼を一時的に凍結しました')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('凍結に失敗しました')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFreezingTagger = false;
        });
      }
    }
  }
}
