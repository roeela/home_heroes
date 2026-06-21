import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:google_sign_in/google_sign_in.dart';

import '../../shared/models/family.dart';
import '../../shared/models/family_user.dart';
import '../../shared/repositories/family_repository.dart';
import '../../shared/repositories/user_repository.dart';

// ── Core Firebase providers ──────────────────────────────────────────────────

final firebaseAuthProvider =
    Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final firestoreProvider =
    Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final googleSignInProvider =
    Provider<GoogleSignIn>((ref) => GoogleSignIn());

// ── Repository providers ─────────────────────────────────────────────────────

final familyRepositoryProvider = Provider<FamilyRepository>(
    (ref) => FamilyRepository(ref.watch(firestoreProvider)));

final userRepositoryProvider = Provider<UserRepository>(
    (ref) => UserRepository(ref.watch(firestoreProvider)));

// ── Auth state stream ─────────────────────────────────────────────────────────

final authStateProvider = StreamProvider<User?>(
    (ref) => ref.watch(firebaseAuthProvider).authStateChanges());

// ── Resolved FamilyUser for the current signed-in Google account ──────────────

final currentFamilyUserProvider = FutureProvider<FamilyUser?>((ref) async {
  final authUser = await ref.watch(authStateProvider.future);
  if (authUser == null || authUser.email == null) return null;

  final repo = ref.watch(userRepositoryProvider);
  final familyUser = await repo.findByEmail(authUser.email!);
  if (familyUser == null) return null;

  // First sign-in: link Firebase UID to the pre-created user doc
  if (familyUser.uid == null) {
    await repo.updateUser(familyUser.familyId, familyUser.docId, {
      'uid': authUser.uid,
      'status': 'active',
      if (authUser.photoURL != null) 'photoUrl': authUser.photoURL,
      if (authUser.displayName != null && familyUser.displayName.isEmpty)
        'displayName': authUser.displayName,
    });
    return familyUser.copyWith(
      uid: authUser.uid,
      status: UserStatus.active,
      photoUrl: authUser.photoURL ?? familyUser.photoUrl,
      displayName:
          authUser.displayName?.isNotEmpty == true ? authUser.displayName : null,
    );
  }

  return familyUser;
});

// ── Auth actions ──────────────────────────────────────────────────────────────

Future<void> signInWithGoogle(WidgetRef ref) async {
  final googleSignIn = ref.read(googleSignInProvider);
  final auth = ref.read(firebaseAuthProvider);

  final googleUser = await googleSignIn.signIn();
  if (googleUser == null) return; // user cancelled

  final googleAuth = await googleUser.authentication;
  final credential = GoogleAuthProvider.credential(
    accessToken: googleAuth.accessToken,
    idToken: googleAuth.idToken,
  );
  await auth.signInWithCredential(credential);
}

Future<void> signOut(WidgetRef ref) async {
  await ref.read(firebaseAuthProvider).signOut();
  await ref.read(googleSignInProvider).signOut();
}

Future<Family> createFamily(WidgetRef ref, String name) async {
  final auth = ref.read(firebaseAuthProvider);
  final userRepo = ref.read(userRepositoryProvider);
  final familyRepo = ref.read(familyRepositoryProvider);
  final authUser = auth.currentUser!;

  final family = await familyRepo.createFamily(name);

  final owner = FamilyUser(
    docId: authUser.email!,
    familyId: family.id,
    displayName: authUser.displayName ?? authUser.email!.split('@').first,
    email: authUser.email!,
    role: UserRole.parent,
    weeklyQuota: 0,
    photoUrl: authUser.photoURL,
    isPrimary: true,
    status: UserStatus.active,
    isActive: true,
    uid: authUser.uid,
  );
  await userRepo.createUser(owner);

  // Invalidate so the router re-evaluates
  ref.invalidate(currentFamilyUserProvider);
  return family;
}
