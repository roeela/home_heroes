import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:home_heroes/core/utils/week_utils.dart';

import '../models/weekly_balance.dart';

class BalanceRepository {
  final FirebaseFirestore _firestore;

  BalanceRepository(this._firestore);

  CollectionReference _balances(String familyId) => _firestore
      .collection('family')
      .doc(familyId)
      .collection('weeklyBalances');

  String _balanceId(String userId, DateTime weekStart) =>
      '${userId}_${weekStartId(weekStart)}';

  Stream<WeeklyBalance?> watchBalance(
      String familyId, String userId, DateTime weekStart) {
    return _balances(familyId)
        .doc(_balanceId(userId, weekStart))
        .snapshots()
        .map((doc) =>
            doc.exists ? WeeklyBalance.fromFirestore(doc, familyId) : null);
  }

  /// Returns balances for a list of child emails for the given week.
  Stream<List<WeeklyBalance>> watchChildrenBalances(
      String familyId, List<String> childEmails, DateTime weekStart) {
    if (childEmails.isEmpty) return Stream.value([]);
    final ids = childEmails.map((e) => _balanceId(e, weekStart)).toList();
    return _balances(familyId)
        .where(FieldPath.documentId, whereIn: ids)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => WeeklyBalance.fromFirestore(doc, familyId))
            .toList());
  }

  /// Creates the balance doc for a child for this week if it doesn't exist,
  /// computing carryover from the previous week.
  Future<WeeklyBalance> ensureBalanceDoc(
    String familyId,
    String userId,
    DateTime weekStart,
    int quota,
  ) async {
    final id = _balanceId(userId, weekStart);
    final ref = _balances(familyId).doc(id);
    final doc = await ref.get();

    if (doc.exists) return WeeklyBalance.fromFirestore(doc, familyId);

    // Compute carryover from the previous week
    final prevWeekStart = weekStart.subtract(const Duration(days: 7));
    final prevDoc =
        await _balances(familyId).doc(_balanceId(userId, prevWeekStart)).get();

    int carryover = 0;
    if (prevDoc.exists) {
      final prev = WeeklyBalance.fromFirestore(prevDoc, familyId);
      carryover = prev.earned - prev.quota + prev.carryover - prev.rewardedPoints;
    }

    final balance = WeeklyBalance(
      id: id,
      userId: userId,
      familyId: familyId,
      weekStart: weekStart,
      quota: quota,
      earned: 0,
      carryover: carryover,
    );
    await ref.set(balance.toFirestore());
    return balance;
  }

  void addEarnedInBatch(WriteBatch batch, String familyId, String userId,
      DateTime weekStart, int points) {
    final ref = _balances(familyId).doc(_balanceId(userId, weekStart));
    batch.update(ref, {'earned': FieldValue.increment(points)});
  }

  // Consumes all available excess — rewarded points won't carry over to next week.
  Future<void> giveReward(
      String familyId, String userId, DateTime weekStart, int excessPoints) async {
    final id = _balanceId(userId, weekStart);
    await _balances(familyId)
        .doc(id)
        .update({'rewardedPoints': FieldValue.increment(excessPoints)});
  }
}
