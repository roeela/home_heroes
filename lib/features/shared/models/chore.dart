import 'package:cloud_firestore/cloud_firestore.dart';

enum ChoreType { recurring, adhoc }

class Chore {
  final String id;
  final String familyId;
  final String name;
  final String description;
  final int score;
  final ChoreType type;
  final int frequency; // recurring: times/week; adhoc: 1
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
      type:
          data['type'] == 'recurring' ? ChoreType.recurring : ChoreType.adhoc,
      frequency: (data['frequency'] as num?)?.toInt() ?? 1,
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
        'isActive': isActive,
        'createdBy': createdBy,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
