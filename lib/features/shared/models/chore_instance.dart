import 'package:cloud_firestore/cloud_firestore.dart';

import 'chore.dart';

enum InstanceStatus { registered, completed, approved, rejected, cancelled }

class ChoreInstance {
  final String id;
  final String familyId;
  final String choreId;
  final String choreName;
  final int choreScore;
  final ChoreType choreType; // denormalized
  final DateTime weekStart;
  final DateTime registeredDay; // midnight of the day the child chose
  final String registeredBy; // child email
  final DateTime? registeredAt;
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
    this.choreType = ChoreType.weeklyPool,
    required this.weekStart,
    required this.registeredDay,
    required this.registeredBy,
    this.registeredAt,
    this.completedAt,
    this.approvedAt,
    this.approvedBy,
    this.status = InstanceStatus.registered,
  });

  factory ChoreInstance.fromFirestore(DocumentSnapshot doc, String familyId) {
    final data = doc.data() as Map<String, dynamic>;
    return ChoreInstance(
      id: doc.id,
      familyId: familyId,
      choreId: data['choreId'] as String,
      choreName: data['choreName'] as String,
      choreScore: (data['choreScore'] as num).toInt(),
      choreType: data['choreType'] == 'specificDay'
          ? ChoreType.specificDay
          : ChoreType.weeklyPool,
      weekStart: (data['weekStart'] as Timestamp).toDate(),
      registeredDay: (data['registeredDay'] as Timestamp).toDate(),
      registeredBy: data['registeredBy'] as String,
      registeredAt: (data['registeredAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      approvedAt: (data['approvedAt'] as Timestamp?)?.toDate(),
      approvedBy: data['approvedBy'] as String?,
      status: InstanceStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => InstanceStatus.registered,
      ),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'choreId': choreId,
        'choreName': choreName,
        'choreScore': choreScore,
        'choreType': choreType.name,
        'weekStart': Timestamp.fromDate(weekStart),
        'registeredDay': Timestamp.fromDate(registeredDay),
        'registeredBy': registeredBy,
        if (registeredAt != null) 'registeredAt': Timestamp.fromDate(registeredAt!),
        if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
        if (approvedAt != null) 'approvedAt': Timestamp.fromDate(approvedAt!),
        if (approvedBy != null) 'approvedBy': approvedBy,
        'status': status.name,
      };

  // True when this instance actively consumes a pool slot.
  bool get isActiveSlot =>
      status == InstanceStatus.registered ||
      status == InstanceStatus.completed ||
      status == InstanceStatus.approved;
}
