import 'package:cloud_firestore/cloud_firestore.dart';

import 'chore.dart';

enum InstanceStatus { open, claimed, completed, approved, rejected }

class ChoreInstance {
  final String id;
  final String familyId;
  final String choreId;
  final String choreName;
  final int choreScore;
  final ChoreType choreType; // denormalized from parent Chore
  final DateTime weekStart;
  final DateTime? scheduledDate; // set for daily instances only (midnight)
  final String? claimedBy; // email of the child who claimed it
  final DateTime? claimedAt;
  final DateTime? completedAt;
  final DateTime? approvedAt;
  final String? approvedBy;
  final InstanceStatus status;

  const ChoreInstance({
    required this.id,
    required this.familyId,
    required this.choreId,
    required this.choreName,
    required this.choreScore,
    this.choreType = ChoreType.weekly,
    required this.weekStart,
    this.scheduledDate,
    this.claimedBy,
    this.claimedAt,
    this.completedAt,
    this.approvedAt,
    this.approvedBy,
    this.status = InstanceStatus.open,
  });

  factory ChoreInstance.fromFirestore(DocumentSnapshot doc, String familyId) {
    final data = doc.data() as Map<String, dynamic>;
    return ChoreInstance(
      id: doc.id,
      familyId: familyId,
      choreId: data['choreId'] as String,
      choreName: data['choreName'] as String,
      choreScore: (data['choreScore'] as num).toInt(),
      choreType: _parseChoreType(data['choreType'] as String?),
      weekStart: (data['weekStart'] as Timestamp).toDate(),
      scheduledDate: (data['scheduledDate'] as Timestamp?)?.toDate(),
      claimedBy: data['claimedBy'] as String?,
      claimedAt: (data['claimedAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      approvedAt: (data['approvedAt'] as Timestamp?)?.toDate(),
      approvedBy: data['approvedBy'] as String?,
      status: InstanceStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => InstanceStatus.open,
      ),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'choreId': choreId,
        'choreName': choreName,
        'choreScore': choreScore,
        'choreType': choreType.name,
        'weekStart': Timestamp.fromDate(weekStart),
        if (scheduledDate != null)
          'scheduledDate': Timestamp.fromDate(scheduledDate!),
        if (claimedBy != null) 'claimedBy': claimedBy,
        if (claimedAt != null) 'claimedAt': Timestamp.fromDate(claimedAt!),
        if (completedAt != null)
          'completedAt': Timestamp.fromDate(completedAt!),
        if (approvedAt != null) 'approvedAt': Timestamp.fromDate(approvedAt!),
        if (approvedBy != null) 'approvedBy': approvedBy,
        'status': status.name,
      };
}

ChoreType _parseChoreType(String? s) {
  switch (s) {
    case 'daily':
      return ChoreType.daily;
    case 'weekly':
      return ChoreType.weekly;
    case 'bonus':
      return ChoreType.bonus;
    case 'recurring':
      return ChoreType.weekly;
    case 'adhoc':
      return ChoreType.bonus;
    default:
      return ChoreType.weekly;
  }
}
