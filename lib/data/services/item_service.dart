import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../models/item_model.dart';
import '../../mock/items/mock_items.dart' as mock_items;

class ItemService {
  ItemService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _gameSessions() =>
      _firestore.collection('gameSessions');

  Future<List<ItemModel>> fetchItemsForGame(String gameId,
      {String visibility = 'RUNNER'}) async {
    if (AppConstants.useMockItems) {
      // Return mock list filtered by visibility
      await Future.delayed(AppConstants.mockApiDelay);
      return mock_items.mockItems
          .where((i) => i.visibility == visibility)
          .toList();
    }

    final snap = await _gameSessions()
        .doc(gameId)
        .collection('items')
        .where('visibility', isEqualTo: visibility)
        .where('state', isEqualTo: 'AVAILABLE')
        .get();

    return snap.docs.map(ItemModel.fromDoc).toList();
  }

  /// Use a FREEZE_TAGGER item: find a nearby tagger within radius and set their
  /// `cooldowns.freezeUntil` to now + configured freeze duration.
  ///
  /// NOTE: This implementation is Flutter-only (client-side). It writes client
  /// timestamps (based on the device clock) into Firestore documents and uses
  /// client SDK transactions to update player documents and events. Because
  /// clients can be tampered with, consider tightening Firestore security
  /// rules to restrict who can write `cooldowns`/`items` or perform server-side
  /// validation later. For development and offline-first gameplay this
  /// Flutter-only approach is supported by the app.
  ///
  /// Returns true if an effect was applied.
  Future<bool> useFreezeTagger({
    required String gameId,
    required String byPlayerId,
    required LatLng position,
  }) async {
    if (AppConstants.useMockItems) {
      await Future.delayed(AppConstants.mockApiDelay);
      // In mock mode, simply return true to indicate success.
      return true;
    }

    final playersRef = _gameSessions().doc(gameId).collection('players');
    final playersSnap = await playersRef.get();

    QueryDocumentSnapshot<Map<String, dynamic>>? target;
    double? bestDist;

    for (final doc in playersSnap.docs) {
      final data = doc.data();
      final role = data['role'] as String? ?? '';
      final status = data['status'] as String? ?? '';
      if (role != 'TAGGER' || status != 'ACTIVE') continue;
      final lastLoc = data['lastLocation'];
      if (lastLoc == null) continue;
      GeoPoint gp;
      if (lastLoc is GeoPoint) {
        gp = lastLoc;
      } else if (lastLoc is Map) {
        gp = GeoPoint((lastLoc['lat'] as num).toDouble(),
            (lastLoc['lng'] as num).toDouble());
      } else {
        continue;
      }

      final d = _distanceMeters(gp.latitude, gp.longitude, position.latitude,
          position.longitude);
      if (d <= AppConstants.itemFreezeRadiusMeters) {
        if (bestDist == null || d < bestDist) {
          bestDist = d;
          target = doc;
        }
      }
    }

    if (target == null) {
      return false;
    }

    final targetRef = target.reference;
    final byPlayerRef = playersRef.doc(byPlayerId);

    // Apply transaction: set freezeUntil on target, decrement item count from byPlayer, and log event
    // Using device time (client-side). UI should compare `cooldowns.freezeUntil` with
    // `DateTime.now().toUtc()` to determine frozen state.
    final freezeUntil = Timestamp.fromDate(
      DateTime.now().toUtc().add(Duration(seconds: AppConstants.itemFreezeDurationSeconds)));

    final success = await _firestore.runTransaction<bool>((tx) async {
      final targetSnap = await tx.get(targetRef);
      if (!targetSnap.exists) return false;

      final bySnap = await tx.get(byPlayerRef);

      // If target is already frozen, abort
      final targetData = targetSnap.data() ?? <String, dynamic>{};
      final cooldowns = targetData['cooldowns'] as Map<String, dynamic>?;
      final existingFreeze = cooldowns != null ? cooldowns['freezeUntil'] as Timestamp? : null;
      final now = DateTime.now().toUtc();
      if (existingFreeze != null && existingFreeze.toDate().isAfter(now)) {
        return false;
      }

      // Check actor has item
      final items = (bySnap.exists ? (bySnap.data()?['items'] as Map<String, dynamic>?) : null) ?? {};
      final key = 'FREEZE_TAGGER';
      final current = (items[key] as num?)?.toInt() ?? 0;
      if (current <= 0) {
        return false;
      }

      // update target cooldowns.freezeUntil
      tx.set(
        targetRef,
        {
          'cooldowns': {
            ...?targetSnap.data()?['cooldowns'] as Map<String, dynamic>?,
            'freezeUntil': freezeUntil,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // decrement item count on the actor
      tx.set(
        byPlayerRef,
        {
          'items': {
            key: current - 1,
          }
        },
        SetOptions(merge: true),
      );

      // append an event
      final eventsRef = _gameSessions().doc(gameId).collection('events').doc();
      tx.set(eventsRef, {
        'eventId': eventsRef.id,
        'type': 'ABILITY_TRIGGERED',
        'payload': {
          'ability': 'FREEZE_TAGGER',
          'byPlayerId': byPlayerId,
          'targetPlayerId': targetRef.id,
          'radiusMeters': AppConstants.itemFreezeRadiusMeters,
          'freezeSeconds': AppConstants.itemFreezeDurationSeconds,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });

      return true;
    }).catchError((_) => false);

    return success;
  }

  /// Use a SEE_TAGGER item: reveal active tagger positions to the caller for
  /// a short duration. Returns a list of {playerId, lat, lng} maps when
  /// successful, or an empty list on failure.
  Future<List<Map<String, dynamic>>> useSeeTagger({
    required String gameId,
    required String byPlayerId,
  }) async {
    if (AppConstants.useMockItems) {
      await Future.delayed(AppConstants.mockApiDelay);
      // In mock mode, return any tagger mock positions (simulate one)
      return [
        {
          'playerId': 'tagger_mock_1',
          'lat': 35.0,
          'lng': 135.0,
        }
      ];
    }

    final playersRef = _gameSessions().doc(gameId).collection('players');
    final playersSnap = await playersRef.get();

    final List<Map<String, dynamic>> taggerPositions = [];
    for (final doc in playersSnap.docs) {
      final data = doc.data();
      final role = data['role'] as String? ?? '';
      final status = data['status'] as String? ?? '';
      if (role != 'TAGGER' || status != 'ACTIVE') continue;
      final lastLoc = data['lastLocation'];
      if (lastLoc == null) continue;
      double lat;
      double lng;
      if (lastLoc is GeoPoint) {
        lat = lastLoc.latitude;
        lng = lastLoc.longitude;
      } else if (lastLoc is Map) {
        lat = (lastLoc['lat'] as num).toDouble();
        lng = (lastLoc['lng'] as num).toDouble();
      } else {
        continue;
      }
      taggerPositions.add({'playerId': doc.id, 'lat': lat, 'lng': lng});
    }

    if (taggerPositions.isEmpty) return [];

    // Attempt to consume an item atomically and append an event with the
    // revealed positions. Returns the positions on success.
    final result = await _firestore.runTransaction<bool>((tx) async {
      final byRef = playersRef.doc(byPlayerId);
      final bySnap = await tx.get(byRef);
      if (!bySnap.exists) return false;
      final items = (bySnap.data()?['items'] as Map<String, dynamic>?) ?? {};
      final key = 'SEE_TAGGER';
      final current = (items[key] as num?)?.toInt() ?? 0;
      if (current <= 0) return false;

      // decrement the item
      tx.set(byRef, {
        'items': {key: current - 1}
      }, SetOptions(merge: true));

      // append an event containing tagger positions and duration
      final eventsRef = _gameSessions().doc(gameId).collection('events').doc();
      tx.set(eventsRef, {
        'eventId': eventsRef.id,
        'type': 'ABILITY_TRIGGERED',
        'payload': {
          'ability': 'SEE_TAGGER',
          'byPlayerId': byPlayerId,
          'positions': taggerPositions,
          'seconds': AppConstants.itemSeeTaggerDurationSeconds,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });

      return true;
    }).catchError((_) => false);

    return result ? taggerPositions : [];
  }

  /// Tagger-only ability: when a tagger has walked enough meters (stored in
  /// their player doc as `walkedMeters`), they can activate this ability to
  /// reveal all active runners' positions for a short duration.
  ///
  /// Runners carrying a FAKE_LOCATION item will automatically consume one charge
  /// and return a fake coordinate to the tagger (decoy) instead of their real
  /// position. This allows another developer to supply the detection event
  /// (tagger reveal) without conflicting with this logic.
  ///
  /// Returns a list of runner positions (possibly fake) on success, or empty on failure.
  Future<List<Map<String, dynamic>>> useTaggerReveal({
    required String gameId,
    required String byPlayerId,
  }) async {
    if (AppConstants.useMockItems) {
      await Future.delayed(AppConstants.mockApiDelay);
      return [
        {'playerId': 'runner_mock_1', 'lat': 35.0002, 'lng': 135.0002}
      ];
    }

    final playersRef = _gameSessions().doc(gameId).collection('players');
    final playersSnap = await playersRef.get();

    final List<_RunnerRevealTarget> runnerTargets = [];
    for (final doc in playersSnap.docs) {
      final data = doc.data();
      final role = data['role'] as String? ?? '';
      final status = data['status'] as String? ?? '';
      if (role != 'RUNNER' || status != 'ACTIVE') continue;
      final lastLoc = data['lastLocation'];
      if (lastLoc == null) continue;
      double lat;
      double lng;
      if (lastLoc is GeoPoint) {
        lat = lastLoc.latitude;
        lng = lastLoc.longitude;
      } else if (lastLoc is Map) {
        lat = (lastLoc['lat'] as num).toDouble();
        lng = (lastLoc['lng'] as num).toDouble();
      } else {
        continue;
      }
      runnerTargets.add(_RunnerRevealTarget(
        ref: doc.reference,
        playerId: doc.id,
        lat: lat,
        lng: lng,
      ));
    }

    if (runnerTargets.isEmpty) return [];

    final positions = await _firestore
        .runTransaction<List<Map<String, dynamic>>>((tx) async {
      final byRef = playersRef.doc(byPlayerId);
      final bySnap = await tx.get(byRef);
      if (!bySnap.exists) return <Map<String, dynamic>>[];
      final byData = bySnap.data() ?? <String, dynamic>{};
      final role = byData['role'] as String? ?? '';
      if (role != 'TAGGER') return <Map<String, dynamic>>[];

      final walked = (byData['walkedMeters'] as num?)?.toDouble() ?? 0.0;
      if (walked < AppConstants.taggerRevealRequiredMeters) {
        return <Map<String, dynamic>>[];
      }

      final List<Map<String, dynamic>> finalPositions = [];
      for (final target in runnerTargets) {
        final runnerSnap = await tx.get(target.ref);
        if (!runnerSnap.exists) continue;
        final runnerData = runnerSnap.data() ?? <String, dynamic>{};
        final items =
            (runnerData['items'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        final currentFake =
            (items['FAKE_LOCATION'] as num?)?.toInt() ?? 0;
        if (currentFake > 0) {
          tx.set(
            target.ref,
            {
              'items': {'FAKE_LOCATION': currentFake - 1},
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          final fakePos = _generateFakeLocation(target.lat, target.lng);
          finalPositions.add({
            'playerId': target.playerId,
            'lat': fakePos['lat'],
            'lng': fakePos['lng'],
          });
        } else {
          finalPositions.add({
            'playerId': target.playerId,
            'lat': target.lat,
            'lng': target.lng,
          });
        }
      }

      if (finalPositions.isEmpty) {
        return <Map<String, dynamic>>[];
      }

      // reset walkedMeters to 0 (consume the charge)
      tx.set(byRef, {
        'walkedMeters': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // append event with runner positions
      final eventsRef = _gameSessions().doc(gameId).collection('events').doc();
      tx.set(eventsRef, {
        'eventId': eventsRef.id,
        'type': 'ABILITY_TRIGGERED',
        'payload': {
          'ability': 'REVEAL_RUNNERS',
          'byPlayerId': byPlayerId,
          'positions': finalPositions,
          'seconds': AppConstants.taggerRevealDurationSeconds,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });

      return finalPositions;
    }).catchError((_) => <Map<String, dynamic>>[]);

    return positions;
  }

  /// Stream items for a game and visibility. Real-time updates ensure that when
  /// an item is picked by one player it disappears for others automatically.
  Stream<List<ItemModel>> watchItemsForGame(String gameId,
      {String visibility = 'RUNNER'}) {
    if (AppConstants.useMockItems) {
      return Stream.value(
        mock_items.mockItems.where((i) => i.visibility == visibility).toList(),
      );
    }

    return _gameSessions()
        .doc(gameId)
        .collection('items')
        .where('visibility', isEqualTo: visibility)
        .snapshots()
        .map((snap) => snap.docs.map(ItemModel.fromDoc).toList());
  }

  /// Attempt to pick an item. Uses a transaction to ensure only one picker can
  /// successfully claim an AVAILABLE item. Returns true if pickup succeeded.
  Future<bool> pickItem({
    required String gameId,
    required String itemId,
    required String pickerPlayerId,
    int runnerMaxItems = 2,
  }) async {
    if (AppConstants.useMockItems) {
      await Future.delayed(AppConstants.mockApiDelay);
      return true;
    }

    final itemRef = _gameSessions().doc(gameId).collection('items').doc(itemId);
    final playerRef = _gameSessions().doc(gameId).collection('players').doc(pickerPlayerId);

    final result = await _firestore.runTransaction<bool>((tx) async {
      final itemSnap = await tx.get(itemRef);
      if (!itemSnap.exists) return false;
      final itemData = itemSnap.data() ?? <String, dynamic>{};
      final state = itemData['state'] as String? ?? 'AVAILABLE';
      if (state != 'AVAILABLE') return false;

      final playerSnap = await tx.get(playerRef);
      if (!playerSnap.exists) return false;
      final playerData = playerSnap.data() ?? <String, dynamic>{};
      final items = (playerData['items'] as Map<String, dynamic>?) ?? {};

      // enforce runner inventory cap
      final totalHeld = items.values.fold<int>(0, (acc, v) => acc + ((v as num?)?.toInt() ?? 0));
      if (totalHeld >= runnerMaxItems) return false;

      final type = itemData['type'] as String? ?? '';
      final current = (items[type] as num?)?.toInt() ?? 0;

      // mark item as picked and increment player's item count
      tx.set(itemRef, {
        'pickedBy': pickerPlayerId,
        'state': 'PICKED',
        'pickedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.set(playerRef, {
        'items': {type: current + 1}
      }, SetOptions(merge: true));

      final eventsRef = _gameSessions().doc(gameId).collection('events').doc();
      tx.set(eventsRef, {
        'eventId': eventsRef.id,
        'type': 'ITEM_PICKED',
        'payload': {
          'itemId': itemRef.id,
          'type': type,
          'byPlayerId': pickerPlayerId,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });

      return true;
    }).catchError((_) => false);

    return result;
  }

  double _distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0; // meters
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _deg2rad(double deg) => deg * (pi / 180.0);

  /// Helper: given a `freezeUntil` Timestamp from a player doc, return true if
  /// the player should be considered frozen according to the local device clock.
  bool isFrozen(Timestamp? freezeUntil) {
    if (freezeUntil == null) return false;
    final now = DateTime.now().toUtc();
    return freezeUntil.toDate().isAfter(now);
  }
}

class _RunnerRevealTarget {
  _RunnerRevealTarget({
    required this.ref,
    required this.playerId,
    required this.lat,
    required this.lng,
  });

  final DocumentReference<Map<String, dynamic>> ref;
  final String playerId;
  final double lat;
  final double lng;
}

Map<String, double> _generateFakeLocation(double lat, double lng) {
  final random = Random();
  final meters = 30 + random.nextDouble() * 20; // 30-50m away
  final bearing = random.nextDouble() * 2 * pi;
  final dLat = (meters * cos(bearing)) / 111320.0;
  final dLng = (meters * sin(bearing)) /
      (111320.0 * cos(lat * pi / 180));
  return {'lat': lat + dLat, 'lng': lng + dLng};
}
