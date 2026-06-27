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

// Balances where the child has an active bonus claim request this week.
final pendingBonusClaimsProvider = Provider<List<WeeklyBalance>>((ref) {
  final balances = ref.watch(childrenBalancesProvider).valueOrNull ?? [];
  return balances.where((b) => b.pendingClaim && b.availableExcess > 0).toList();
});

// ── Actions ───────────────────────────────────────────────────────────────────

Future<void> approveChore(WidgetRef ref, ChoreInstance instance) async {
  final user = ref.read(currentFamilyUserProvider).valueOrNull;
  if (user == null) return;

  final children = ref.read(childrenProvider).valueOrNull ?? [];
  final child =
      children.where((c) => c.email == instance.registeredBy).firstOrNull;
  if (child == null) return;

  // Use the week the chore was registered for, not necessarily the current week.
  // This ensures cross-week approvals credit the correct balance.
  final weekStart = getWeekStart(instance.registeredDay);
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

Future<void> deleteChore(WidgetRef ref, Chore chore) async {
  final user = ref.read(currentFamilyUserProvider).valueOrNull;
  if (user == null) return;
  final instanceRepo = ref.read(instanceRepositoryProvider);
  final choreRepo = ref.read(choreRepositoryProvider);
  await instanceRepo.cancelActiveInstancesForChore(user.familyId, chore.id);
  await choreRepo.deactivateChore(user.familyId, chore.id);
}
