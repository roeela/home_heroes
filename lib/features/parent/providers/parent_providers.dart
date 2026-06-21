import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/week_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../../shared/models/chore.dart';
import '../../shared/models/chore_instance.dart';
import '../../shared/models/family_user.dart';
import '../../shared/models/weekly_balance.dart';
import '../../shared/repositories/balance_repository.dart';
import '../../shared/repositories/chore_repository.dart';
import '../../shared/repositories/instance_repository.dart';

// ── Repository providers (shared via this file by child providers too) ────────

final choreRepositoryProvider = Provider<ChoreRepository>(
    (ref) => ChoreRepository(ref.watch(firestoreProvider)));

final instanceRepositoryProvider = Provider<InstanceRepository>(
    (ref) => InstanceRepository(ref.watch(firestoreProvider)));

final balanceRepositoryProvider = Provider<BalanceRepository>(
    (ref) => BalanceRepository(ref.watch(firestoreProvider)));

// ── Stream providers ──────────────────────────────────────────────────────────

final choreListProvider = StreamProvider<List<Chore>>((ref) {
  final user = ref.watch(currentFamilyUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref.watch(choreRepositoryProvider).watchChores(user.familyId);
});

final pendingApprovalProvider = StreamProvider<List<ChoreInstance>>((ref) {
  final user = ref.watch(currentFamilyUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref
      .watch(instanceRepositoryProvider)
      .watchPendingApproval(user.familyId);
});

final childrenProvider = StreamProvider<List<FamilyUser>>((ref) {
  final user = ref.watch(currentFamilyUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref.watch(userRepositoryProvider).watchChildren(user.familyId);
});

final childrenBalancesProvider = StreamProvider<List<WeeklyBalance>>((ref) {
  final user = ref.watch(currentFamilyUserProvider).valueOrNull;
  final children = ref.watch(childrenProvider).valueOrNull ?? [];
  if (user == null) return Stream.value([]);

  final weekStart = getWeekStart();
  final emails = children.map((c) => c.email).toList();
  return ref
      .watch(balanceRepositoryProvider)
      .watchChildrenBalances(user.familyId, emails, weekStart);
});

// ── Approval action ───────────────────────────────────────────────────────────

Future<void> approveChore(
    WidgetRef ref, ChoreInstance instance) async {
  final user = ref.read(currentFamilyUserProvider).valueOrNull;
  if (user == null || instance.claimedBy == null) return;

  final children = ref.read(childrenProvider).valueOrNull ?? [];
  final child = children.where((c) => c.email == instance.claimedBy).firstOrNull;
  if (child == null) return;

  final weekStart = getWeekStart();
  final balanceRepo = ref.read(balanceRepositoryProvider);
  await balanceRepo.ensureBalanceDoc(
      user.familyId, child.email, weekStart, child.weeklyQuota);

  final firestore = ref.read(firestoreProvider);
  final instanceRepo = ref.read(instanceRepositoryProvider);
  final batch = firestore.batch();
  instanceRepo.approveInstanceInBatch(
      batch, user.familyId, instance.id, user.email);
  balanceRepo.addEarnedInBatch(
      batch, user.familyId, child.email, weekStart, instance.choreScore);
  await batch.commit();
}
