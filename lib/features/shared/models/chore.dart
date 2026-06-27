import 'package:cloud_firestore/cloud_firestore.dart';

enum ChoreType { weeklyPool, specificDay }

class Chore {
  final String id;
  final String familyId;
  final String name;
  final String description;
  final int score;
  final ChoreType type;
  final int availablePerWeek; // weeklyPool: 1–7; specificDay: scheduledDates.length
  final List<DateTime> scheduledDates; // specificDay only: actual calendar dates
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
    this.scheduledDates = const [],
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
      scheduledDates: (data['scheduledDates'] as List<dynamic>?)
              ?.map((e) => (e as Timestamp).toDate())
              .toList() ??
          [],
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
        'scheduledDates': scheduledDates.map(Timestamp.fromDate).toList(),
        'isActive': isActive,
        'createdBy': createdBy,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
