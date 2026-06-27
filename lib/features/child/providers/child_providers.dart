import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/week_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../../parent/providers/parent_providers.dart';
import '../../shared/models/chore.dart';
import '../../shared/models/chore_instance.dart';
import '../../shared/models/family_user.dart';
import '../../shared/models/weekly_balance.dart';

// The Sunday of the current Israel week — still used for balance docs and lookback.
final currentWeekStartProvider = Provider<DateTime>((_) => getWeekStart());

// Midnight of today — start of the rolling 7-day window.
final todayProvider = Provider<DateTime>((_) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
});

// End of the rolling window: today + 6 days (inclusive).
final windowEndProvider = Provider<DateTime>((ref) {
  final today = ref.watch(todayProvider);
  return today.add(const Duration(days: 6));
});

// All instances whose registeredDay falls in [today, today+6].
// Used to compute pool availability for the day picker.
final weekAllInstancesProvider = StreamProvider<List<ChoreInstance>>((ref) {
  final user = ref.watch(currentFamilyUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  final today = ref.watch(todayProvider);
  final end = ref.watch(windowEndProvider);
  return ref
      .watch(instanceRepositoryProvider)
      .watchWindowInstances(user.familyId, today, end);
});

// This child's own registrations from the current week start through today+6.
// Starts at currentWeekStart so completed/approved items from earlier this week
// remain visible in the My Tasks tab.
final myRegistrationsProvider = StreamProvider<List<ChoreInstance>>((ref) {
  final user = ref.watch(currentFamilyUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  final weekStart = ref.watch(currentWeekStartProvider);
  final end = ref.watch(windowEndProvider);
  return ref
      .watch(instanceRepositoryProvider)
      .watchMyRegistrations(user.familyId, user.email, weekStart, end);
});

// Active chores visible to this child in the rolling window.
// weeklyPool: always visible while active.
// specificDay: visible if any scheduledDate falls in [today, today+6].
final visibleChoresProvider = Provider<List<Chore>>((ref) {
  final allChores = ref.watch(choreListProvider).valueOrNull ?? [];
  final today = ref.watch(todayProvider);
  final end = ref.watch(windowEndProvider);
  return allChores.where((chore) {
    if (chore.type == ChoreType.weeklyPool) return true;
    return chore.scheduledDates.any(
        (d) => !d.isBefore(today) && !d.isAfter(end));
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
