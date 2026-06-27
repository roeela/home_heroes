import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/week_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../../parent/providers/parent_providers.dart';
import '../../shared/models/chore.dart';
import '../../shared/models/chore_instance.dart';
import '../../shared/models/family_user.dart';
import '../../shared/models/weekly_balance.dart';

final currentWeekStartProvider = Provider<DateTime>((_) => getWeekStart());

// All instances for the current week — used to compute pool availability.
final weekAllInstancesProvider = StreamProvider<List<ChoreInstance>>((ref) {
  final user = ref.watch(currentFamilyUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  final weekStart = ref.watch(currentWeekStartProvider);
  return ref
      .watch(instanceRepositoryProvider)
      .watchWeekInstances(user.familyId, weekStart);
});

// This child's own registrations for the current week.
final myRegistrationsProvider = StreamProvider<List<ChoreInstance>>((ref) {
  final user = ref.watch(currentFamilyUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  final weekStart = ref.watch(currentWeekStartProvider);
  return ref
      .watch(instanceRepositoryProvider)
      .watchMyRegistrations(user.familyId, user.email, weekStart);
});

// Active chores visible to this child this week.
// weeklyPool: always visible while active.
// specificDay: visible only if choreWeekStart matches the current week.
final visibleChoresProvider = Provider<List<Chore>>((ref) {
  final allChores = ref.watch(choreListProvider).valueOrNull ?? [];
  final weekStart = ref.watch(currentWeekStartProvider);
  return allChores.where((chore) {
    if (chore.type == ChoreType.weeklyPool) return true;
    // specificDay: only show for the week it was created for
    final cws = chore.choreWeekStart;
    if (cws == null) return false;
    return cws.year == weekStart.year &&
        cws.month == weekStart.month &&
        cws.day == weekStart.day;
  }).toList();
});

final myBalanceStreamProvider = StreamProvider<WeeklyBalance?>((ref) {
  final user = ref.watch(currentFamilyUserProvider).valueOrNull;
  if (user == null || user.role != UserRole.child) return Stream.value(null);
  final weekStart = ref.watch(currentWeekStartProvider);
  return ref
      .watch(balanceRepositoryProvider)
      .watchBalance(user.familyId, user.email, weekStart);
});
