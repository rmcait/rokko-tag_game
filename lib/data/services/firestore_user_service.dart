import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/firebase_user_model.dart' as auth_model;
import '../models/firestore_user_model.dart';

class FirestoreUserService {
  FirestoreUserService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Future<UserModel?> fetchSampleUser() async {
    final snapshot =
        await _users.orderBy('updatedAt', descending: true).limit(1).get();
    if (snapshot.docs.isEmpty) {
      return null;
    }
    return UserModel.fromDoc(snapshot.docs.first);
  }

  Future<void> touchUser(String userId) async {
    await _users.doc(userId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Firebase Auth のユーザー情報を Firestore の users/{uid} に反映する。
  Future<void> syncFromAuthUser(auth_model.UserModel authUser) async {
    final docRef = _users.doc(authUser.uid);
    final snapshot = await docRef.get();

    final payload = {
      'googleUid': authUser.uid,
      'userId': authUser.uid,
      'displayName': authUser.displayName,
      'email': authUser.email,
      'avatarUrl': authUser.photoUrl,
      'status': 'ACTIVE',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (snapshot.exists) {
      await docRef.set(payload, SetOptions(merge: true));
    } else {
      await docRef.set({
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
