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

  // Returns the calendar date for a given day offset within the week.
  // day: 0=Sun, 1=Mon, …, 6=Sat. weekStart is always a Sunday.
  DateTime _resolveWeekdayDate(DateTime weekStart, int day) =>
      DateTime(weekStart.year, weekStart.month, weekStart.day + day);

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
        throw Exception('משימה זו כבר נתפסה');
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

  /// Creates instances for all active chores that don't yet have instances this week.
  Future<void> ensureWeekInitialized(
      String familyId, DateTime weekStart, List<Chore> activeChores) async {
    final weekTimestamp = Timestamp.fromDate(weekStart);
    final existing = await _instances(familyId)
        .where('weekStart', isEqualTo: weekTimestamp)
        .get();

    // Build idempotency structures from existing instances.
    final Set<String> dailyKeys = {}; // '${choreId}_${day}-${month}'
    final Map<String, int> weeklyCount = {}; // choreId → instance count

    for (final doc in existing.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final choreId = data['choreId'] as String;
      final type = data['choreType'] as String?;
      final scheduledTs = data['scheduledDate'] as Timestamp?;

      if (type == 'daily' && scheduledTs != null) {
        final d = scheduledTs.toDate();
        dailyKeys.add('${choreId}_${d.day}-${d.month}');
      } else {
        weeklyCount[choreId] = (weeklyCount[choreId] ?? 0) + 1;
      }
    }

    final batch = _firestore.batch();
    var hasChanges = false;

    for (final chore in activeChores) {
      switch (chore.type) {
        case ChoreType.daily:
          for (final day in chore.days) {
            final scheduledDate = _resolveWeekdayDate(weekStart, day);
            final key = '${chore.id}_${scheduledDate.day}-${scheduledDate.month}';
            if (!dailyKeys.contains(key)) {
              final ref = _instances(familyId).doc();
              batch.set(
                  ref,
                  ChoreInstance(
                    id: ref.id,
                    familyId: familyId,
                    choreId: chore.id,
                    choreName: chore.name,
                    choreScore: chore.score,
                    choreType: ChoreType.daily,
                    weekStart: weekStart,
                    scheduledDate: scheduledDate,
                  ).toFirestore());
              hasChanges = true;
            }
          }

        case ChoreType.weekly:
          final existing = weeklyCount[chore.id] ?? 0;
          final needed = chore.frequency - existing;
          for (int i = 0; i < needed; i++) {
            final ref = _instances(familyId).doc();
            batch.set(
                ref,
                ChoreInstance(
                  id: ref.id,
                  familyId: familyId,
                  choreId: chore.id,
                  choreName: chore.name,
                  choreScore: chore.score,
                  choreType: ChoreType.weekly,
                  weekStart: weekStart,
                ).toFirestore());
            hasChanges = true;
          }

        case ChoreType.bonus:
          break; // created manually at form submission time
      }
    }

    if (hasChanges) await batch.commit();
  }

  /// Creates one instance per scheduled day for a new daily chore (called at form save).
  Future<void> createDailyInstancesForWeek(
      String familyId, Chore chore, DateTime weekStart) async {
    final batch = _firestore.batch();
    for (final day in chore.days) {
      final scheduledDate = _resolveWeekdayDate(weekStart, day);
      final ref = _instances(familyId).doc();
      batch.set(
          ref,
          ChoreInstance(
            id: ref.id,
            familyId: familyId,
            choreId: chore.id,
            choreName: chore.name,
            choreScore: chore.score,
            choreType: ChoreType.daily,
            weekStart: weekStart,
            scheduledDate: scheduledDate,
          ).toFirestore());
    }
    await batch.commit();
  }

  /// Creates `frequency` instances for a new weekly chore (called at form save).
  Future<void> createWeeklyInstancesForWeek(
      String familyId, Chore chore, DateTime weekStart) async {
    final batch = _firestore.batch();
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
            choreType: ChoreType.weekly,
            weekStart: weekStart,
          ).toFirestore());
    }
    await batch.commit();
  }

  /// Creates a single bonus instance immediately (called at form save).
  Future<void> createBonusInstance(
      String familyId, Chore chore, DateTime weekStart) async {
    final ref = _instances(familyId).doc();
    await ref.set(ChoreInstance(
      id: ref.id,
      familyId: familyId,
      choreId: chore.id,
      choreName: chore.name,
      choreScore: chore.score,
      choreType: ChoreType.bonus,
      weekStart: weekStart,
    ).toFirestore());
  }
}
