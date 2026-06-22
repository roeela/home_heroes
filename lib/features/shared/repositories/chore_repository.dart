import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chore.dart';

class ChoreRepository {
  final FirebaseFirestore _firestore;

  ChoreRepository(this._firestore);

  CollectionReference _chores(String familyId) =>
      _firestore.collection('family').doc(familyId).collection('chores');

  Stream<List<Chore>> watchChores(String familyId) {
    return _chores(familyId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Chore.fromFirestore(doc, familyId))
            .toList());
  }

  Future<List<Chore>> getActiveChores(String familyId) async {
    final snap =
        await _chores(familyId).where('isActive', isEqualTo: true).get();
    return snap.docs.map((doc) => Chore.fromFirestore(doc, familyId)).toList();
  }

  Future<Chore> createChore({
    required String familyId,
    required String name,
    required String description,
    required int score,
    required ChoreType type,
    required int frequency,
    required List<int> days,
    required String createdBy,
  }) async {
    final doc = _chores(familyId).doc();
    final chore = Chore(
      id: doc.id,
      familyId: familyId,
      name: name,
      description: description,
      score: score,
      type: type,
      frequency: frequency,
      days: days,
      isActive: true,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );
    await doc.set(chore.toFirestore());
    return chore;
  }

  Future<void> updateChore(Chore chore) async {
    final data = chore.toFirestore();
    data.remove('createdAt');
    data.remove('createdBy');
    await _chores(chore.familyId).doc(chore.id).update(data);
  }

  Future<void> deleteChore(String familyId, String choreId) async {
    await _chores(familyId).doc(choreId).update({'isActive': false});
  }
}
