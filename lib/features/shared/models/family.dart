import 'package:cloud_firestore/cloud_firestore.dart';

class Family {
  final String id;
  final String name;
  final DateTime createdAt;

  const Family({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory Family.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Family(
      id: doc.id,
      name: data['name'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
