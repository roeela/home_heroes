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
              icon: Icon(Icons.list_alt_rounded), label: 'משימות'),
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
    final excess = balance?.availableExcess ?? 0;
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
          if (carryover < 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'חוב משבוע קודם: $carryover נק׳',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.red[700],
                    fontWeight: FontWeight.w500),
              ),
            ),
          if (excess > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(children: [
                Icon(Icons.stars_rounded, color: Colors.amber[700], size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'עודף לפרס: +$excess נק׳',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.amber[800],
                        fontWeight: FontWeight.w600),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber[700],
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 32),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => _giveReward(ref, context, excess),
                  child: const Text('תן פרס'),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Future<void> _giveReward(
      WidgetRef ref, BuildContext context, int excess) async {
    final user = ref.read(currentFamilyUserProvider).valueOrNull;
    if (user == null) return;
    await ref.read(balanceRepositoryProvider).giveReward(
        user.familyId, child.email, getWeekStart(), excess);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('פרס ניתן ל${child.displayName}! ($excess נק׳)')),
      );
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
              child: Text('אין משימות עדיין.\nלחץ + כדי להוסיף.',
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
        heroTag: 'fab_add_chore',
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

  static const _dayNames = {
    0: 'א׳', 1: 'ב׳', 2: 'ג׳', 3: 'ד׳', 4: 'ה׳', 5: 'ו׳', 6: 'ש׳'
  };

  (IconData, String) get _typeDisplay {
    switch (chore.type) {
      case ChoreType.weeklyPool:
        return (Icons.repeat_rounded, 'עד ${chore.availablePerWeek}× בשבוע');
      case ChoreType.specificDay:
        final dates = chore.scheduledDates
            .map((d) => '${_dayNames[d.weekday % 7] ?? ''} ${d.day}/${d.month}')
            .join(', ');
        return (Icons.calendar_today_rounded, dates);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, subtitle) = _typeDisplay;
    return ListTile(
      leading: Icon(icon),
      title: Text(chore.name),
      subtitle: Text(subtitle),
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
        title: const Text('מחיקת משימה'),
        content: Text('למחוק את "${chore.name}"?\n\nכל הרישומים הפתוחים יבוטלו.'),
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
      try {
        await deleteChore(ref, chore);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('שגיאה: $e')));
        }
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
    final bonusClaims = ref.watch(pendingBonusClaimsProvider);
    final children = ref.watch(childrenProvider).valueOrNull ?? [];

    return pendingAsync.when(
      loading: () => const AppLoading(),
      error: (e, _) => Center(child: Text('שגיאה: $e')),
      data: (instances) {
        final isEmpty = instances.isEmpty && bonusClaims.isEmpty;
        if (isEmpty) {
          return const Center(
            child: Text('אין פעולות הממתינות לאישור.',
                style: TextStyle(fontSize: 16)),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            if (bonusClaims.isNotEmpty) ...[
              _SectionLabel(label: 'בקשות פרס'),
              ...bonusClaims.map((b) => _BonusClaimCard(balance: b, children: children)),
              if (instances.isNotEmpty) const SizedBox(height: 8),
            ],
            if (instances.isNotEmpty) ...[
              _SectionLabel(label: 'אישור משימות'),
              ...instances.map((i) => _ApprovalCard(instance: i, children: children)),
            ],
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(label,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

class _BonusClaimCard extends ConsumerWidget {
  final WeeklyBalance balance;
  final List<FamilyUser> children;
  const _BonusClaimCard({required this.balance, required this.children});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childName = children
            .where((c) => c.email == balance.userId)
            .firstOrNull
            ?.displayName ??
        balance.userId;
    final excess = balance.availableExcess;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.card_giftcard_rounded, color: Colors.amber[700]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(childName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('+$excess נק׳',
                  style: TextStyle(
                      color: Colors.amber[800], fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 4),
          Text('מבקש/ת לממש עודף נקודות כפרס',
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.amber[700]),
              onPressed: () => _award(ref, context, excess),
              icon: const Icon(Icons.star_rounded),
              label: const Text('תן פרס'),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _award(WidgetRef ref, BuildContext context, int excess) async {
    final user = ref.read(currentFamilyUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref.read(balanceRepositoryProvider).giveReward(
          user.familyId, balance.userId, balance.weekStart, excess);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('פרס ניתן! ($excess נק׳ מומשו)')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('שגיאה: $e')));
      }
    }
  }
}

class _ApprovalCard extends ConsumerWidget {
  final ChoreInstance instance;
  final List<FamilyUser> children;
  const _ApprovalCard({required this.instance, required this.children});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childName = children
            .where((c) => c.email == instance.registeredBy)
            .firstOrNull
            ?.displayName ??
        instance.registeredBy;

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
          Text(
            'יום: ${instance.registeredDay.day}/${instance.registeredDay.month}',
            style: const TextStyle(fontSize: 13),
          ),
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

enum _MemberAction { reset, remove }

class _FamilyTab extends ConsumerWidget {
  const _FamilyTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentFamilyUserProvider).valueOrNull;
    final membersAsync = currentUser != null
        ? ref.watch(_allMembersProvider(currentUser.familyId))
        : ref.watch(childrenProvider);

    return Scaffold(
      body: membersAsync.when(
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
                  PopupMenuButton<_MemberAction>(
                    onSelected: (action) {
                      if (action == _MemberAction.reset) {
                        _confirmReset(context, ref, m);
                      } else {
                        _confirmRemove(context, ref, m);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: _MemberAction.reset,
                        child: ListTile(
                          leading: Icon(Icons.restart_alt_rounded),
                          title: Text('איפוס'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: _MemberAction.remove,
                        child: ListTile(
                          leading: Icon(Icons.person_remove_rounded,
                              color: Colors.red),
                          title: Text('הסר',
                              style: TextStyle(color: Colors.red)),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
              ]),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_add_member',
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

  Future<void> _confirmReset(
      BuildContext context, WidgetRef ref, FamilyUser member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('איפוס משתמש'),
        content: Text(
            'לאפס את ${member.displayName}?\n\nפעולה זו תמחק את כל יתרות הנקודות ותבטל את כל הרישומים שלקח/ה.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('אפס')),
        ],
      ),
    );
    if (ok == true) {
      final user = ref.read(currentFamilyUserProvider).valueOrNull;
      if (user == null) return;
      await Future.wait([
        ref
            .read(balanceRepositoryProvider)
            .deleteUserBalances(user.familyId, member.email),
        ref
            .read(instanceRepositoryProvider)
            .cancelUserRegistrations(user.familyId, member.email),
      ]);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${member.displayName} אופס בהצלחה')),
        );
      }
    }
  }
}

// Provider for ALL family members (not just children)
final _allMembersProvider =
    StreamProvider.family<List<FamilyUser>, String>((ref, familyId) {
  return ref.watch(userRepositoryProvider).watchMembers(familyId);
});
