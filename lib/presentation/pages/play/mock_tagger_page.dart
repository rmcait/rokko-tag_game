import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tag_game/core/constants/app_constants.dart';
import 'package:tag_game/data/services/item_service.dart';

class MockTaggerPage extends StatefulWidget {
  final String? partyId;
  final String gameId;
  final String currentUserId;

  const MockTaggerPage({super.key, this.partyId, required this.gameId, required this.currentUserId});

  @override
  State<MockTaggerPage> createState() => _MockTaggerPageState();
}

class _MockTaggerPageState extends State<MockTaggerPage> {
  GoogleMapController? _mapController;
  LatLng _position = const LatLng(35.0, 135.0);
  final ItemService _itemService = ItemService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  double _walkedMeters = 0.0;
  double get _progress => (_walkedMeters / AppConstants.taggerRevealRequiredMeters).clamp(0.0, 1.0);

  Set<Marker> _revealMarkers = {};
  DateTime? _revealExpiresAt;
  // freeze state
  bool _isFrozen = false;
  Timestamp? _freezeUntil;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _playerSub;

  // small move step in meters for D-pad
  static const double _moveStepMeters = 10.0; // tagger moves faster in mock

  @override
  void initState() {
    super.initState();
    _subscribePlayerDoc();
  }

  Future<void> _subscribePlayerDoc() async {
    final docRef = _firestore.collection('gameSessions').doc(widget.gameId).collection('players').doc(widget.currentUserId);
    // fetch initial
    final snap = await docRef.get();
    if (snap.exists) {
      final data = snap.data() ?? {};
      setState(() {
        _walkedMeters = (data['walkedMeters'] as num?)?.toDouble() ?? 0.0;
        final lastLoc = data['lastLocation'];
        if (lastLoc is GeoPoint) {
          _position = LatLng(lastLoc.latitude, lastLoc.longitude);
        }
      });
    }

    _playerSub = docRef.snapshots().listen((s) {
      final data = s.data();
      if (data == null) return;
      final walked = (data['walkedMeters'] as num?)?.toDouble() ?? _walkedMeters;
      // check cooldowns.freezeUntil
      Timestamp? freezeTs;
      try {
        final cooldowns = data['cooldowns'] as Map<String, dynamic>?;
        freezeTs = cooldowns != null ? (cooldowns['freezeUntil'] as Timestamp?) : null;
      } catch (_) {
        freezeTs = null;
      }

      final frozen = _itemService.isFrozen(freezeTs);

      setState(() {
        _walkedMeters = walked;
        _isFrozen = frozen;
        _freezeUntil = freezeTs;
      });
    });
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _mapController?.moveCamera(CameraUpdate.newLatLngZoom(_position, 16));
  }

  LatLng _offsetLatLng(LatLng from, double eastMeters, double northMeters) {
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

  void _moveByMeters({required double eastMeters, required double northMeters}) async {
    if (_isFrozen) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('凍結中で移動できません')));
      return;
    }

    final newPos = _offsetLatLng(_position, eastMeters, northMeters);
    final moved = _distanceMeters(_position, newPos);
    setState(() {
      _position = newPos;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(_position));

    // persist walkedMeters and lastLocation
    final playerRef = _firestore.collection('gameSessions').doc(widget.gameId).collection('players').doc(widget.currentUserId);
    await playerRef.set({
      'walkedMeters': FieldValue.increment(moved),
      'lastLocation': GeoPoint(_position.latitude, _position.longitude),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // local optimistic update
    setState(() {
      _walkedMeters += moved;
    });
  }

  Future<void> _onPressReveal() async {
    if (_progress < 1.0) return;
    final positions = await _itemService.useTaggerReveal(gameId: widget.gameId, byPlayerId: widget.currentUserId);
    if (positions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('位置情報を取得できませんでした')));
      return;
    }

    final List<Marker> markers = [];
    for (final p in positions) {
      final mid = MarkerId('runner_${p['playerId']}');
      markers.add(Marker(markerId: mid, position: LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed), infoWindow: InfoWindow(title: 'Runner ${p['playerId']}')));
    }

    setState(() {
      _revealMarkers = markers.toSet();
      _revealExpiresAt = DateTime.now().toUtc().add(Duration(seconds: AppConstants.taggerRevealDurationSeconds));
    });

    Future.delayed(Duration(seconds: AppConstants.taggerRevealDurationSeconds), () {
      if (mounted) {
        setState(() {
          _revealMarkers = {};
          _revealExpiresAt = null;
          _walkedMeters = 0.0; // server also resets, keep UI in sync
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mock Tagger - 鬼')), 
      body: SafeArea(
        child: Stack(
          children: [
            GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(target: _position, zoom: 16),
              markers: {
                Marker(markerId: const MarkerId('me'), position: _position, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue), infoWindow: InfoWindow(title: widget.currentUserId)),
                ..._revealMarkers,
              },
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      if (_isFrozen)
                        Column(
                          children: [
                            const Icon(Icons.ac_unit, color: Colors.blueAccent),
                            const SizedBox(height: 6),
                            Text(_freezeUntil != null
                                ? 'Frozen: ${_freezeUntil!.toDate().difference(DateTime.now().toUtc()).inSeconds.clamp(0, 999)}s'
                                : 'Frozen'),
                            const SizedBox(height: 8),
                          ],
                        ),
                      Text('Charge: ${( _progress * 100 ).toStringAsFixed(0)}%'),
                      const SizedBox(height: 8),
                      SizedBox(width: 140, child: LinearProgressIndicator(value: _progress)),
                      const SizedBox(height: 8),
                      Text('${_walkedMeters.toStringAsFixed(1)} / ${AppConstants.taggerRevealRequiredMeters.toStringAsFixed(0)} m'),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _progress >= 1.0 ? _onPressReveal : null,
                        child: const Text('Reveal Runners'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // D-pad
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
                      Align(
                        alignment: const Alignment(0, -0.8),
                        child: _dpadButton('up', Icons.arrow_upward, () => _moveByMeters(eastMeters: 0, northMeters: _moveStepMeters)),
                      ),
                      Align(
                        alignment: const Alignment(0, 0.8),
                        child: _dpadButton('down', Icons.arrow_downward, () => _moveByMeters(eastMeters: 0, northMeters: -_moveStepMeters)),
                      ),
                      Align(
                        alignment: const Alignment(-0.8, 0),
                        child: _dpadButton('left', Icons.arrow_back, () => _moveByMeters(eastMeters: -_moveStepMeters, northMeters: 0)),
                      ),
                      Align(
                        alignment: const Alignment(0.8, 0),
                        child: _dpadButton('right', Icons.arrow_forward, () => _moveByMeters(eastMeters: _moveStepMeters, northMeters: 0)),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                          child: const Center(child: Icon(Icons.my_location)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_revealExpiresAt != null)
              Positioned(
                left: 12,
                bottom: 12,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('Reveal ends in ${_revealExpiresAt!.difference(DateTime.now().toUtc()).inSeconds}s'),
                  ),
                ),
              ),
          ],
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
        onPressed: _isFrozen ? null : onPressed,
        child: Icon(icon),
      ),
    );
  }
}
