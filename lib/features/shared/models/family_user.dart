import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { parent, child }

enum UserStatus { pending, active }

class FamilyUser {
  final String docId; // email used as document ID
  final String familyId;
  final String displayName;
  final String email;
  final UserRole role;
  final int weeklyQuota;
  final String? photoUrl;
  final bool isPrimary;
  final UserStatus status;
  final bool isActive;
  final String? uid; // Firebase Auth UID, null until first sign-in

  const FamilyUser({
    required this.docId,
    required this.familyId,
    required this.displayName,
    required this.email,
    required this.role,
    this.weeklyQuota = 0,
    this.photoUrl,
    this.isPrimary = false,
    this.status = UserStatus.pending,
    this.isActive = true,
    this.uid,
  });

  factory FamilyUser.fromFirestore(DocumentSnapshot doc, String familyId) {
    final data = doc.data() as Map<String, dynamic>;
    return FamilyUser(
      docId: doc.id,
      familyId: familyId,
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String? ?? doc.id,
      role: data['role'] == 'parent' ? UserRole.parent : UserRole.child,
      weeklyQuota: (data['weeklyQuota'] as num?)?.toInt() ?? 0,
      photoUrl: data['photoUrl'] as String?,
      isPrimary: data['isPrimary'] as bool? ?? false,
      status:
          data['status'] == 'active' ? UserStatus.active : UserStatus.pending,
      isActive: data['isActive'] as bool? ?? true,
      uid: data['uid'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'displayName': displayName,
        'email': email,
        'role': role.name,
        'weeklyQuota': weeklyQuota,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'isPrimary': isPrimary,
        'status': status.name,
        'isActive': isActive,
        if (uid != null) 'uid': uid,
      };

  FamilyUser copyWith({
    String? displayName,
    String? photoUrl,
    UserStatus? status,
    bool? isActive,
    String? uid,
    int? weeklyQuota,
  }) {
    return FamilyUser(
      docId: docId,
      familyId: familyId,
      displayName: displayName ?? this.displayName,
      email: email,
      role: role,
      weeklyQuota: weeklyQuota ?? this.weeklyQuota,
      photoUrl: photoUrl ?? this.photoUrl,
      isPrimary: isPrimary,
      status: status ?? this.status,
      isActive: isActive ?? this.isActive,
      uid: uid ?? this.uid,
    );
  }
}
