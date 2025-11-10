import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';

class FirestoreUserService {
  FirestoreUserService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Future<UserModel?> fetchSampleUser() async {
    final snapshot = await _users.orderBy('updatedAt', descending: true).limit(1).get();
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
}
