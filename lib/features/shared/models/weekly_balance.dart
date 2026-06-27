import 'package:cloud_firestore/cloud_firestore.dart';

class WeeklyBalance {
  final String id; // '{userEmail}_{weekStartId}'
  final String userId; // email
  final String familyId;
  final DateTime weekStart;
  final int quota;
  final int earned;
  final int carryover; // positive = excess carried in; negative = debt carried in
  final int rewardedPoints; // excess consumed by rewards this week
  final bool pendingClaim; // child has requested a bonus award

  const WeeklyBalance({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.weekStart,
    required this.quota,
    this.earned = 0,
    this.carryover = 0,
    this.rewardedPoints = 0,
    this.pendingClaim = false,
  });

  int get remaining => quota - earned;
  int get netEarned => earned + carryover;
  bool get metQuota => earned >= quota;

  // Points available to redeem as a real-life reward (zeroed when parent gives reward)
  int get availableExcess {
    final net = earned + carryover - quota - rewardedPoints;
    return net > 0 ? net : 0;
  }

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
      rewardedPoints: (data['rewardedPoints'] as num?)?.toInt() ?? 0,
      pendingClaim: (data['pendingClaim'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'weekStart': Timestamp.fromDate(weekStart),
        'quota': quota,
        'earned': earned,
        'carryover': carryover,
        'rewardedPoints': rewardedPoints,
        'pendingClaim': pendingClaim,
      };
}
