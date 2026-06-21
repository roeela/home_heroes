import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/week_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../../parent/providers/parent_providers.dart';
import '../../parent/screens/add_member_screen.dart';
import '../../parent/screens/chore_form_screen.dart';
import '../../shared/models/chore.dart';
import '../../shared/models/chore_instance.dart';
import '../../shared/models/family_user.dart';
import '../../shared/models/weekly_balance.dart';
import '../../shared/widgets/app_loading.dart';
import '../../shared/widgets/score_chip.dart';

class ParentDashboard extends ConsumerStatefulWidget {
  const ParentDashboard({super.key});

  @override
  ConsumerState<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends ConsumerState<ParentDashboard> {
  int _tab = 0;

  static const _tabs = [
    _OverviewTab(),
    _ChoresTab(),
    _ApprovalTab(),
    _FamilyTab(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initWeek());
  }

  Future<void> _initWeek() async {
    final user = ref.read(currentFamilyUserProvider).valueOrNull;
    if (user == null) return;
    final chores =
        await ref.read(choreRepositoryProvider).getActiveChores(user.familyId);
    await ref
        .read(instanceRepositoryProvider)
        .ensureWeekInitialized(user.familyId, getWeekStart(), chores);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HomeHeroes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'יציאה',
            onPressed: () => signOut(ref),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_rounded), label: 'סקירה'),
          NavigationDestination(
              icon: Icon(Icons.list_alt_rounded), label: 'תורנויות'),
          NavigationDestination(
              icon: Icon(Icons.check_circle_outline_rounded),
              label: 'אישורים'),
          NavigationDestination(
              icon: Icon(Icons.group_rounded), label: 'משפחה'),
        ],
      ),
    );
  }
}

// ── Tab 0: Overview ───────────────────────────────────────────────────────────

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(childrenProvider);
    final balances = ref.watch(childrenBalancesProvider);
    final weekStart = getWeekStart();

    return children.when(
      loading: () => const AppLoading(),
      error: (e, _) => Center(child: Text('שגיאה: $e')),
      data: (kids) {
        if (kids.isEmpty) {
          return const Center(
            child: Text('אין ילדים עדיין.\nהוסף ילדים בלשונית המשפחה.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16)),
          );
        }
        final bals = balances.valueOrNull ?? [];
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: kids.length,
          itemBuilder: (_, i) {
            final child = kids[i];
            final bal =
                bals.where((b) => b.userId == child.email).firstOrNull;
            return _ChildCard(
                child: child, balance: bal, weekLabel: weekLabel(weekStart));
          },
        );
      },
    );
  }
}

class _ChildCard extends ConsumerWidget {
  final FamilyUser child;
  final WeeklyBalance? balance;
  final String weekLabel;

  const _ChildCard(
      {required this.child, required this.balance, required this.weekLabel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earned = balance?.earned ?? 0;
    final quota = child.weeklyQuota;
    final carryover = balance?.carryover ?? 0;
    final progress = quota > 0 ? (earned / quota).clamp(0.0, 1.0) : 0.0;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              child: Text(child.displayName.isNotEmpty
                  ? child.displayName[0]
                  : '?'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(child.displayName,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            ScoreChip(score: earned),
          ]),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('$earned / $quota נקודות',
                style: const TextStyle(fontSize: 13)),
            Text(weekLabel,
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onSurfaceVariant)),
          ]),
          if (carryover != 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                carryover > 0
                    ? 'עודף משבוע קודם: +$carryover נק׳'
                    : 'חוב משבוע קודם: $carryover נק׳',
                style: TextStyle(
                    fontSize: 12,
                    color: carryover > 0 ? Colors.green[700] : Colors.red[700],
                    fontWeight: FontWeight.w500),
              ),
            ),
          // Reset carryover button (for any parent)
          if (carryover != 0)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('אפס יתרה', style: TextStyle(fontSize: 12)),
                onPressed: () => _resetCarryover(ref, context),
              ),
            ),
        ]),
      ),
    );
  }

  Future<void> _resetCarryover(WidgetRef ref, BuildContext context) async {
    final user = ref.read(currentFamilyUserProvider).valueOrNull;
    if (user == null) return;
    await ref.read(balanceRepositoryProvider).resetCarryover(
        user.familyId, child.email, getWeekStart());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('היתרה אופסה')));
    }
  }
}

// ── Tab 1: Chores ─────────────────────────────────────────────────────────────

class _ChoresTab extends ConsumerWidget {
  const _ChoresTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choresAsync = ref.watch(choreListProvider);

    return Scaffold(
      body: choresAsync.when(
        loading: () => const AppLoading(),
        error: (e, _) => Center(child: Text('שגיאה: $e')),
        data: (chores) {
          if (chores.isEmpty) {
            return const Center(
              child: Text('אין תורנויות עדיין.\nלחץ + כדי להוסיף.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
            );
          }
          return ListView.builder(
            itemCount: chores.length,
            itemBuilder: (_, i) => _ChoreItem(chore: chores[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ChoreFormScreen())),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ChoreItem extends ConsumerWidget {
  final Chore chore;
  const _ChoreItem({required this.chore});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(chore.type == ChoreType.recurring
          ? Icons.repeat_rounded
          : Icons.flash_on_rounded),
      title: Text(chore.name),
      subtitle: Text(chore.type == ChoreType.recurring
          ? '${chore.frequency}× בשבוע'
          : 'חד-פעמי'),
      trailing: ScoreChip(score: chore.score),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChoreFormScreen(existing: chore))),
      onLongPress: () => _confirmDelete(context, ref),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('מחיקת תורנות'),
        content: Text('למחוק את "${chore.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('מחק')),
        ],
      ),
    );
    if (ok == true) {
      final user = ref.read(currentFamilyUserProvider).valueOrNull;
      if (user != null) {
        await ref
            .read(choreRepositoryProvider)
            .deleteChore(user.familyId, chore.id);
      }
    }
  }
}

// ── Tab 2: Approval queue ─────────────────────────────────────────────────────

class _ApprovalTab extends ConsumerWidget {
  const _ApprovalTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingApprovalProvider);
    final children = ref.watch(childrenProvider).valueOrNull ?? [];

    return pendingAsync.when(
      loading: () => const AppLoading(),
      error: (e, _) => Center(child: Text('שגיאה: $e')),
      data: (instances) {
        if (instances.isEmpty) {
          return const Center(
            child: Text('אין פעולות הממתינות לאישור.',
                style: TextStyle(fontSize: 16)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: instances.length,
          itemBuilder: (_, i) => _ApprovalCard(
              instance: instances[i], children: children),
        );
      },
    );
  }
}

class _ApprovalCard extends ConsumerWidget {
  final ChoreInstance instance;
  final List<FamilyUser> children;
  const _ApprovalCard({required this.instance, required this.children});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childName = children
            .where((c) => c.email == instance.claimedBy)
            .firstOrNull
            ?.displayName ??
        instance.claimedBy ?? '?';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(instance.choreName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ScoreChip(score: instance.choreScore),
          ]),
          const SizedBox(height: 4),
          Text('בוצע על ידי: $childName',
              style: const TextStyle(fontSize: 14)),
          if (instance.completedAt != null)
            Text(
              'הושלם: ${_fmt(instance.completedAt!)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _reject(ref, context),
                icon: const Icon(Icons.close, color: Colors.red),
                label: const Text('דחה',
                    style: TextStyle(color: Colors.red)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _approve(ref, context),
                icon: const Icon(Icons.check),
                label: const Text('אשר'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Future<void> _approve(WidgetRef ref, BuildContext context) async {
    try {
      await approveChore(ref, instance);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('שגיאה: $e')));
      }
    }
  }

  Future<void> _reject(WidgetRef ref, BuildContext context) async {
    final user = ref.read(currentFamilyUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref
          .read(instanceRepositoryProvider)
          .rejectInstance(user.familyId, instance.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('שגיאה: $e')));
      }
    }
  }
}

// ── Tab 3: Family management ──────────────────────────────────────────────────

class _FamilyTab extends ConsumerWidget {
  const _FamilyTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(
        childrenProvider.select((a) => a)); // all children
    final currentUser = ref.watch(currentFamilyUserProvider).valueOrNull;
    final allMembersAsync = currentUser != null
        ? ref.watch(_allMembersProvider(currentUser.familyId))
        : null;

    return Scaffold(
      body: (allMembersAsync ?? membersAsync).when(
        loading: () => const AppLoading(),
        error: (e, _) => Center(child: Text('שגיאה: $e')),
        data: (members) => ListView.builder(
          itemCount: members.length,
          itemBuilder: (_, i) {
            final m = members[i];
            return ListTile(
              leading: CircleAvatar(
                child: Text(
                    m.displayName.isNotEmpty ? m.displayName[0] : '?'),
              ),
              title: Text(m.displayName),
              subtitle: Text(m.email),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                _roleBadge(m.role),
                if (m.status == UserStatus.pending)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Chip(
                        label: Text('ממתין',
                            style: TextStyle(fontSize: 11))),
                  ),
                if (currentUser?.isPrimary == true &&
                    m.email != currentUser!.email)
                  IconButton(
                    icon: const Icon(Icons.person_remove_rounded,
                        color: Colors.red),
                    onPressed: () => _confirmRemove(context, ref, m),
                  ),
              ]),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddMemberScreen())),
        child: const Icon(Icons.person_add_rounded),
      ),
    );
  }

  Widget _roleBadge(UserRole role) {
    return Chip(
      label: Text(role == UserRole.parent ? 'הורה' : 'ילד',
          style: const TextStyle(fontSize: 11)),
      backgroundColor:
          role == UserRole.parent ? Colors.blue[50] : Colors.green[50],
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, FamilyUser member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('הסרת בן משפחה'),
        content: Text('להסיר את ${member.displayName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('הסר')),
        ],
      ),
    );
    if (ok == true) {
      final user = ref.read(currentFamilyUserProvider).valueOrNull;
      if (user != null) {
        await ref
            .read(userRepositoryProvider)
            .deactivateUser(user.familyId, member.docId);
      }
    }
  }
}

// Provider for ALL family members (not just children)
final _allMembersProvider =
    StreamProvider.family<List<FamilyUser>, String>((ref, familyId) {
  return ref.watch(userRepositoryProvider).watchMembers(familyId);
});
