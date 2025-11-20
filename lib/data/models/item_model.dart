import 'package:cloud_firestore/cloud_firestore.dart';

enum ItemType {
  seeTagger,
  fakeLocation,
  freezeTagger,
  trap,
  freezeAll,
}

extension ItemTypeExt on ItemType {
  String get code {
    switch (this) {
      case ItemType.seeTagger:
        return 'SEE_TAGGER';
      case ItemType.fakeLocation:
        return 'FAKE_LOCATION';
      case ItemType.freezeTagger:
        return 'FREEZE_TAGGER';
      case ItemType.trap:
        return 'TRAP';
      case ItemType.freezeAll:
        return 'FREEZE_ALL';
    }
  }

  static ItemType fromCode(String? code) {
    switch (code) {
      case 'SEE_TAGGER':
        return ItemType.seeTagger;
      case 'FAKE_LOCATION':
        return ItemType.fakeLocation;
      case 'FREEZE_TAGGER':
        return ItemType.freezeTagger;
      case 'TRAP':
        return ItemType.trap;
      case 'FREEZE_ALL':
        return ItemType.freezeAll;
      default:
        return ItemType.seeTagger;
    }
  }
}

class ItemModel {
  final String itemId;
  final ItemType type;
  final String visibility;
  final double lat;
  final double lng;
  final Timestamp spawnedAt;
  final String? pickedBy;
  final String state;

  ItemModel({
    required this.itemId,
    required this.type,
    required this.visibility,
    required this.lat,
    required this.lng,
    required this.spawnedAt,
    this.pickedBy,
    required this.state,
  });

  factory ItemModel.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return ItemModel(
      itemId: doc.id,
      type: ItemTypeExt.fromCode(d['type'] as String?),
      visibility: d['visibility'] as String? ?? 'RUNNER',
      lat: (d['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (d['lng'] as num?)?.toDouble() ?? 0.0,
      spawnedAt: d['spawnedAt'] as Timestamp? ?? Timestamp.now(),
      pickedBy: d['pickedBy'] as String?,
      state: d['state'] as String? ?? 'AVAILABLE',
    );
  }
}
