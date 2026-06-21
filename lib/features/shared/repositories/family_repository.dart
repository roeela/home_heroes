import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/family.dart';

class FamilyRepository {
  final FirebaseFirestore _firestore;

  FamilyRepository(this._firestore);

  CollectionReference get _families => _firestore.collection('family');

  Future<Family> createFamily(String name) async {
    final doc = _families.doc();
    final family = Family(id: doc.id, name: name, createdAt: DateTime.now());
    await doc.set(family.toFirestore());
    return family;
  }

  Future<Family?> getFamily(String familyId) async {
    final doc = await _families.doc(familyId).get();
    if (!doc.exists) return null;
    return Family.fromFirestore(doc);
  }
}
