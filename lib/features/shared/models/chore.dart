import 'package:cloud_firestore/cloud_firestore.dart';

enum ChoreType { daily, weekly, bonus }

ChoreType _parseChoreType(String? s) {
  switch (s) {
    case 'daily':
      return ChoreType.daily;
    case 'weekly':
      return ChoreType.weekly;
    case 'bonus':
      return ChoreType.bonus;
    case 'recurring':
      return ChoreType.weekly; // backward compat
    case 'adhoc':
      return ChoreType.bonus; // backward compat
    default:
      return ChoreType.weekly;
  }
}

class Chore {
  final String id;
  final String familyId;
  final String name;
  final String description;
  final int score;
  final ChoreType type;
  final int frequency; // weekly: times/week; daily: days.length; bonus: 1
  final List<int> days; // 0=Sun … 6=Sat; only used for daily type
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
    this.frequency = 1,
    this.days = const [],
    this.isActive = true,
    required this.createdBy,
    required this.createdAt,
  });

  factory Chore.fromFirestore(DocumentSnapshot doc, String familyId) {
    final data = doc.data() as Map<String, dynamic>;
    return Chore(
      id: doc.id,
      familyId: familyId,
      name: data['name'] as String,
      description: data['description'] as String? ?? '',
      score: (data['score'] as num).toInt(),
      type: _parseChoreType(data['type'] as String?),
      frequency: (data['frequency'] as num?)?.toInt() ?? 1,
      days: (data['days'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
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
        'frequency': frequency,
        'days': days,
        'isActive': isActive,
        'createdBy': createdBy,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
