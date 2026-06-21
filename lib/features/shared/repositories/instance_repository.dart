import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chore.dart';
import '../models/chore_instance.dart';

class InstanceRepository {
  final FirebaseFirestore _firestore;

  InstanceRepository(this._firestore);

  CollectionReference _instances(String familyId) => _firestore
      .collection('family')
      .doc(familyId)
      .collection('choreInstances');

  Stream<List<ChoreInstance>> watchOpenInstances(
      String familyId, DateTime weekStart) {
    return _instances(familyId)
        .where('status', isEqualTo: 'open')
        .where('weekStart', isEqualTo: Timestamp.fromDate(weekStart))
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ChoreInstance.fromFirestore(doc, familyId))
            .toList());
  }

  Stream<List<ChoreInstance>> watchMyInstances(
      String familyId, String userEmail, DateTime weekStart) {
    return _instances(familyId)
        .where('claimedBy', isEqualTo: userEmail)
        .where('weekStart', isEqualTo: Timestamp.fromDate(weekStart))
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ChoreInstance.fromFirestore(doc, familyId))
            .toList());
  }

  Stream<List<ChoreInstance>> watchPendingApproval(String familyId) {
    return _instances(familyId)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ChoreInstance.fromFirestore(doc, familyId))
            .toList());
  }

  Stream<List<ChoreInstance>> watchWeekInstances(
      String familyId, String userEmail, DateTime weekStart) {
    return _instances(familyId)
        .where('claimedBy', isEqualTo: userEmail)
        .where('weekStart', isEqualTo: Timestamp.fromDate(weekStart))
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ChoreInstance.fromFirestore(doc, familyId))
            .toList());
  }

  Future<void> claimInstance(
      String familyId, String instanceId, String userEmail) async {
    final ref = _instances(familyId).doc(instanceId);
    await _firestore.runTransaction((txn) async {
      final doc = await txn.get(ref);
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null || data['status'] != 'open') {
        throw Exception('תורנות זו כבר נתבעה');
      }
      txn.update(ref, {
        'status': 'claimed',
        'claimedBy': userEmail,
        'claimedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> markCompleted(String familyId, String instanceId) async {
    await _instances(familyId).doc(instanceId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  void approveInstanceInBatch(WriteBatch batch, String familyId,
      String instanceId, String approverEmail) {
    final ref = _instances(familyId).doc(instanceId);
    batch.update(ref, {
      'status': 'approved',
      'approvedBy': approverEmail,
      'approvedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rejectInstance(String familyId, String instanceId) async {
    await _instances(familyId).doc(instanceId).update({
      'status': 'open',
      'claimedBy': FieldValue.delete(),
      'claimedAt': FieldValue.delete(),
      'completedAt': FieldValue.delete(),
    });
  }

  /// Creates instances for all recurring chores for the given week if none exist yet.
  Future<void> ensureWeekInitialized(
      String familyId, DateTime weekStart, List<Chore> activeChores) async {
    final weekTimestamp = Timestamp.fromDate(weekStart);
    final existing = await _instances(familyId)
        .where('weekStart', isEqualTo: weekTimestamp)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) return;

    final batch = _firestore.batch();
    for (final chore in activeChores) {
      if (chore.type == ChoreType.recurring) {
        for (int i = 0; i < chore.frequency; i++) {
          final ref = _instances(familyId).doc();
          batch.set(
              ref,
              ChoreInstance(
                id: ref.id,
                familyId: familyId,
                choreId: chore.id,
                choreName: chore.name,
                choreScore: chore.score,
                weekStart: weekStart,
              ).toFirestore());
        }
      }
    }
    await batch.commit();
  }

  Future<void> createAdhocInstance(
      String familyId, Chore chore, DateTime weekStart) async {
    final ref = _instances(familyId).doc();
    await ref.set(ChoreInstance(
      id: ref.id,
      familyId: familyId,
      choreId: chore.id,
      choreName: chore.name,
      choreScore: chore.score,
      weekStart: weekStart,
    ).toFirestore());
  }
}
