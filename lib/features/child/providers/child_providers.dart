import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/week_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../../parent/providers/parent_providers.dart';
import '../../shared/models/chore_instance.dart';
import '../../shared/models/family_user.dart';
import '../../shared/models/weekly_balance.dart';

final currentWeekStartProvider = Provider<DateTime>((_) => getWeekStart());

final openInstancesProvider = StreamProvider<List<ChoreInstance>>((ref) {
  final user = ref.watch(currentFamilyUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  final weekStart = ref.watch(currentWeekStartProvider);
  return ref
      .watch(instanceRepositoryProvider)
      .watchOpenInstances(user.familyId, weekStart);
});

final myInstancesProvider = StreamProvider<List<ChoreInstance>>((ref) {
  final user = ref.watch(currentFamilyUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  final weekStart = ref.watch(currentWeekStartProvider);
  return ref
      .watch(instanceRepositoryProvider)
      .watchMyInstances(user.familyId, user.email, weekStart);
});

final myBalanceStreamProvider = StreamProvider<WeeklyBalance?>((ref) {
  final user = ref.watch(currentFamilyUserProvider).valueOrNull;
  if (user == null || user.role != UserRole.child) return Stream.value(null);
  final weekStart = ref.watch(currentWeekStartProvider);
  return ref
      .watch(balanceRepositoryProvider)
      .watchBalance(user.familyId, user.email, weekStart);
});
