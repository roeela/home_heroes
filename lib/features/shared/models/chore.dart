import 'package:cloud_firestore/cloud_firestore.dart';

enum ChoreType { weeklyPool, specificDay }

class Chore {
  final String id;
  final String familyId;
  final String name;
  final String description;
  final int score;
  final ChoreType type;
  final int availablePerWeek; // weeklyPool: 1–7; specificDay: scheduledDays.length
  final List<int> scheduledDays; // specificDay only: 0=Sun … 6=Sat
  final DateTime? choreWeekStart; // specificDay only: Sunday of the week it was created for
  final bool isActive;
  final String createdBy;
  final DateTime createdAt;

  const Chore({
    required this.id,
    required this.familyId,
    required this.name,
    this.description = '',
    required this.score,
    required this.type,
    this.availablePerWeek = 1,
    this.scheduledDays = const [],
    this.choreWeekStart,
    this.isActive = true,
    required this.createdBy,
    required this.createdAt,
  });

  factory Chore.fromFirestore(DocumentSnapshot doc, String familyId) {
    final data = doc.data() as Map<String, dynamic>;
    final type =
        data['type'] == 'specificDay' ? ChoreType.specificDay : ChoreType.weeklyPool;
    return Chore(
      id: doc.id,
      familyId: familyId,
      name: data['name'] as String,
      description: data['description'] as String? ?? '',
      score: (data['score'] as num).toInt(),
      type: type,
      availablePerWeek: (data['availablePerWeek'] as num?)?.toInt() ?? 1,
      scheduledDays: (data['scheduledDays'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
      choreWeekStart: (data['choreWeekStart'] as Timestamp?)?.toDate(),
      isActive: data['isActive'] as bool? ?? true,
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'description': description,
        'score': score,
        'type': type.name,
        'availablePerWeek': availablePerWeek,
        'scheduledDays': scheduledDays,
        if (choreWeekStart != null)
          'choreWeekStart': Timestamp.fromDate(choreWeekStart!),
        'isActive': isActive,
        'createdBy': createdBy,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
