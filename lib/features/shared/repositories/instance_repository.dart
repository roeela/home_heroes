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

  // All instances for the current week (all children, all statuses).
  // Used by the child home screen to compute pool availability.
  Stream<List<ChoreInstance>> watchWeekInstances(
      String familyId, DateTime weekStart) {
    return _instances(familyId)
        .where('weekStart', isEqualTo: Timestamp.fromDate(weekStart))
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ChoreInstance.fromFirestore(doc, familyId))
            .toList());
  }

  // A child's own registrations for the current week (all statuses).
  Stream<List<ChoreInstance>> watchMyRegistrations(
      String familyId, String userEmail, DateTime weekStart) {
    return _instances(familyId)
        .where('registeredBy', isEqualTo: userEmail)
        .where('weekStart', isEqualTo: Timestamp.fromDate(weekStart))
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ChoreInstance.fromFirestore(doc, familyId))
            .toList());
  }

  // Completed instances awaiting parent approval (current week only).
  Stream<List<ChoreInstance>> watchPendingApproval(
      String familyId, DateTime weekStart) {
    return _instances(familyId)
        .where('weekStart', isEqualTo: Timestamp.fromDate(weekStart))
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ChoreInstance.fromFirestore(doc, familyId))
            .toList());
  }

  // Register a child for a chore on a specific day.
  // Uses a transaction to prevent double-registration on the same day.
  Future<void> registerForDay(
    String familyId,
    Chore chore,
    DateTime day, // midnight local time of the target day
    String childEmail,
    DateTime weekStart,
  ) async {
    final dayTs = Timestamp.fromDate(day);
    final weekTs = Timestamp.fromDate(weekStart);

    await _firestore.runTransaction((txn) async {
      // Check the day isn't already taken by someone else.
      final existing = await _instances(familyId)
          .where('choreId', isEqualTo: chore.id)
          .where('registeredDay', isEqualTo: dayTs)
          .where('weekStart', isEqualTo: weekTs)
          .get();

      final activeThatDay = existing.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final s = data['status'] as String?;
        return s == 'registered' || s == 'completed' || s == 'approved';
      });
      if (activeThatDay.isNotEmpty) {
        throw Exception('היום הזה כבר נלקח');
      }

      final ref = _instances(familyId).doc();
      txn.set(
        ref,
        ChoreInstance(
          id: ref.id,
          familyId: familyId,
          choreId: chore.id,
          choreName: chore.name,
          choreScore: chore.score,
          choreType: chore.type,
          weekStart: weekStart,
          registeredDay: day,
          registeredBy: childEmail,
          registeredAt: DateTime.now(),
        ).toFirestore(),
      );
    });
  }

  // Unregister a child from a specific day slot.
  Future<void> unregister(String familyId, String instanceId) async {
    await _instances(familyId)
        .doc(instanceId)
        .update({'status': InstanceStatus.cancelled.name});
  }

  Future<void> markCompleted(String familyId, String instanceId) async {
    await _instances(familyId).doc(instanceId).update({
      'status': InstanceStatus.completed.name,
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  void approveInstanceInBatch(WriteBatch batch, String familyId,
      String instanceId, String approverEmail) {
    final ref = _instances(familyId).doc(instanceId);
    batch.update(ref, {
      'status': InstanceStatus.approved.name,
      'approvedBy': approverEmail,
      'approvedAt': FieldValue.serverTimestamp(),
    });
  }

  // Rejection frees the slot (status=rejected is not counted in pool).
  Future<void> rejectInstance(String familyId, String instanceId) async {
    await _instances(familyId).doc(instanceId).update({
      'status': InstanceStatus.rejected.name,
    });
  }

  // Cancel all registered/completed instances for a user (used on member reset).
  Future<void> cancelUserRegistrations(
      String familyId, String userEmail) async {
    final snap = await _instances(familyId)
        .where('registeredBy', isEqualTo: userEmail)
        .get();

    final toCancel = snap.docs.where((doc) {
      final s = (doc.data() as Map<String, dynamic>)['status'] as String?;
      return s == 'registered' || s == 'completed';
    }).toList();

    if (toCancel.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in toCancel) {
      batch.update(doc.reference, {'status': InstanceStatus.cancelled.name});
    }
    await batch.commit();
  }

  // Cancel all registered/completed instances for a chore (used on chore delete).
  Future<void> cancelActiveInstancesForChore(
      String familyId, String choreId) async {
    final snap = await _instances(familyId)
        .where('choreId', isEqualTo: choreId)
        .get();

    final toCancel = snap.docs.where((doc) {
      final s = (doc.data() as Map<String, dynamic>)['status'] as String?;
      return s == 'registered' || s == 'completed';
    }).toList();

    if (toCancel.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in toCancel) {
      batch.update(doc.reference, {'status': InstanceStatus.cancelled.name});
    }
    await batch.commit();
  }
}
