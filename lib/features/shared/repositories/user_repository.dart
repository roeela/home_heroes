import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/family_user.dart';

class UserRepository {
  final FirebaseFirestore _firestore;

  UserRepository(this._firestore);

  CollectionReference _users(String familyId) =>
      _firestore.collection('family').doc(familyId).collection('users');

  /// Find a user by email across all families — used on sign-in before family is known.
  Future<FamilyUser?> findByEmail(String email) async {
    final query = await _firestore
        .collectionGroup('users')
        .where('email', isEqualTo: email)
        .where('isActive', isEqualTo: true)
        .get();

    if (query.docs.isEmpty) return null;

    final doc = query.docs.first;
    // path: family/{familyId}/users/{docId}
    final familyId = doc.reference.path.split('/')[1];
    return FamilyUser.fromFirestore(doc, familyId);
  }

  Future<void> createUser(FamilyUser user) async {
    await _users(user.familyId).doc(user.docId).set(user.toFirestore());
  }

  Future<void> updateUser(
      String familyId, String docId, Map<String, dynamic> updates) async {
    await _users(familyId).doc(docId).update(updates);
  }

  Future<void> deactivateUser(String familyId, String docId) async {
    await _users(familyId).doc(docId).update({'isActive': false});
  }

  Stream<List<FamilyUser>> watchMembers(String familyId) {
    return _users(familyId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => FamilyUser.fromFirestore(doc, familyId))
            .toList());
  }

  Stream<List<FamilyUser>> watchChildren(String familyId) {
    return _users(familyId)
        .where('role', isEqualTo: 'child')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => FamilyUser.fromFirestore(doc, familyId))
            .toList());
  }

  Future<FamilyUser?> getUser(String familyId, String docId) async {
    final doc = await _users(familyId).doc(docId).get();
    if (!doc.exists) return null;
    return FamilyUser.fromFirestore(doc, familyId);
  }
}
