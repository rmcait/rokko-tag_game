import '../../data/models/item_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final List<ItemModel> mockItems = [
  ItemModel(
    itemId: 'itm_mock_1',
    type: ItemType.freezeTagger,
    visibility: 'RUNNER',
    lat: 35.0,
    lng: 135.0,
    spawnedAt: Timestamp.now(),
    pickedBy: null,
    state: 'AVAILABLE',
  ),
  ItemModel(
    itemId: 'itm_mock_2',
    type: ItemType.seeTagger,
    visibility: 'RUNNER',
    lat: 35.0001,
    lng: 135.0001,
    spawnedAt: Timestamp.now(),
    pickedBy: null,
    state: 'AVAILABLE',
  ),
  ItemModel(
    itemId: 'itm_mock_3',
    type: ItemType.fakeLocation,
    visibility: 'RUNNER',
    lat: 35.0002,
    lng: 135.0002,
    spawnedAt: Timestamp.now(),
    pickedBy: null,
    state: 'AVAILABLE',
  ),
];
