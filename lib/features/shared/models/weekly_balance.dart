import 'package:cloud_firestore/cloud_firestore.dart';

class WeeklyBalance {
  final String id; // '{userEmail}_{weekStartId}'
  final String userId; // email
  final String familyId;
  final DateTime weekStart;
  final int quota;
  final int earned;
  final int carryover; // positive = excess carried in; negative = debt carried in

  const WeeklyBalance({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.weekStart,
    required this.quota,
    this.earned = 0,
    this.carryover = 0,
  });

  int get remaining => quota - earned;
  int get netEarned => earned + carryover;
  bool get metQuota => earned >= quota;

  factory WeeklyBalance.fromFirestore(DocumentSnapshot doc, String familyId) {
    final data = doc.data() as Map<String, dynamic>;
    return WeeklyBalance(
      id: doc.id,
      userId: data['userId'] as String,
      familyId: familyId,
      weekStart: (data['weekStart'] as Timestamp).toDate(),
      quota: (data['quota'] as num).toInt(),
      earned: (data['earned'] as num?)?.toInt() ?? 0,
      carryover: (data['carryover'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'weekStart': Timestamp.fromDate(weekStart),
        'quota': quota,
        'earned': earned,
        'carryover': carryover,
      };
}
