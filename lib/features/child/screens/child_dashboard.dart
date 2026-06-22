import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/week_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../../child/providers/child_providers.dart';
import '../../parent/providers/parent_providers.dart';
import '../../shared/models/chore.dart';
import '../../shared/models/chore_instance.dart';
import '../../shared/widgets/app_loading.dart';
import '../../shared/widgets/score_chip.dart';

class ChildDashboard extends ConsumerStatefulWidget {
  const ChildDashboard({super.key});

  @override
  ConsumerState<ChildDashboard> createState() => _ChildDashboardState();
}

class _ChildDashboardState extends ConsumerState<ChildDashboard> {
  int _tab = 0;

  static const _tabs = [
    _HomeTab(),
    _MyChoresTab(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initWeek();
      await _ensureBalance();
    });
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

  Future<void> _ensureBalance() async {
    final user = ref.read(currentFamilyUserProvider).valueOrNull;
    if (user == null) return;
    final weekStart = ref.read(currentWeekStartProvider);
    await ref
        .read(balanceRepositoryProvider)
        .ensureBalanceDoc(user.familyId, user.email, weekStart, user.weeklyQuota);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentFamilyUserProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text('שלום, ${user?.displayName.split(' ').first ?? ''}!'),
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
              icon: Icon(Icons.home_rounded), label: 'הבית'),
          NavigationDestination(
              icon: Icon(Icons.assignment_rounded), label: 'המשימות שלי'),
        ],
      ),
    );
  }
}

// ── Tab 0: Home (goal + today's tasks + available this week) ──────────────────

class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(myBalanceStreamProvider);
    final openAsync = ref.watch(openInstancesProvider);
    final user = ref.watch(currentFamilyUserProvider).valueOrNull;
    final weekStart = ref.watch(currentWeekStartProvider);

    return balanceAsync.when(
      loading: () => const AppLoading(),
      error: (e, _) => Center(child: Text('שגיאה: $e')),
      data: (balance) {
        final quota = user?.weeklyQuota ?? 0;
        final earned = balance?.earned ?? 0;
        final carryover = balance?.carryover ?? 0;
        final excess = balance?.availableExcess ?? 0;
        final progress =
            quota > 0 ? (earned / quota).clamp(0.0, 1.0) : 0.0;
        final colorScheme = Theme.of(context).colorScheme;

        final allOpen = openAsync.valueOrNull ?? [];
        final today = DateTime.now();
        final todayInstances = allOpen
            .where((i) =>
                i.choreType == ChoreType.daily &&
                i.scheduledDate != null &&
                i.scheduledDate!.year == today.year &&
                i.scheduledDate!.month == today.month &&
                i.scheduledDate!.day == today.day)
            .toList();
        final weekInstances = allOpen
            .where((i) =>
                i.choreType == ChoreType.weekly ||
                i.choreType == ChoreType.bonus)
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Weekly goal card ───────────────────────────────────────────
              Text(weekLabel(weekStart),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 15, color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              Center(
                child: SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 12,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('$earned',
                          style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary)),
                      Text('מתוך $quota נק׳',
                          style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant)),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              _StatRow(
                  label: 'הרוויחת השבוע',
                  value: '$earned נקודות',
                  icon: Icons.star_rounded,
                  color: colorScheme.primary),
              const SizedBox(height: 8),
              _StatRow(
                  label: 'נותר להשלמת המכסה',
                  value: '${(quota - earned).clamp(0, quota)} נקודות',
                  icon: Icons.flag_rounded,
                  color: colorScheme.secondary),
              if (carryover != 0) ...[
                const SizedBox(height: 8),
                _StatRow(
                    label: carryover > 0
                        ? 'עודף משבוע שעבר'
                        : 'חוב משבוע שעבר',
                    value: '${carryover > 0 ? '+' : ''}$carryover נקודות',
                    icon: carryover > 0
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    color: carryover > 0
                        ? Colors.green[700]!
                        : Colors.red[700]!),
              ],
              if (excess > 0) ...[
                const SizedBox(height: 8),
                _StatRow(
                    label: 'נקודות לפרס',
                    value: '+$excess נקודות',
                    icon: Icons.card_giftcard_rounded,
                    color: Colors.amber[700]!),
              ],
              if (earned >= quota && quota > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.celebration_rounded, color: Colors.green),
                      SizedBox(width: 8),
                      Text('כל הכבוד! השלמת את המכסה השבועית! 🎉',
                          style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],

              // ── Today's tasks ──────────────────────────────────────────────
              const SizedBox(height: 28),
              _SectionHeader(
                title: 'משימות היום',
                subtitle:
                    '${today.day}/${today.month}',
              ),
              const SizedBox(height: 8),
              if (openAsync.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (todayInstances.isEmpty)
                _EmptySection(label: 'אין משימות יומיות להיום')
              else
                ...todayInstances.map((i) => _TaskCard(instance: i)),

              // ── Available this week ────────────────────────────────────────
              const SizedBox(height: 24),
              const _SectionHeader(title: 'זמין השבוע'),
              const SizedBox(height: 8),
              if (openAsync.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (weekInstances.isEmpty)
                _EmptySection(label: 'אין משימות פתוחות השבוע')
              else
                ...weekInstances.map((i) => _TaskCard(instance: i)),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      if (subtitle != null) ...[
        const SizedBox(width: 8),
        Text(subtitle!,
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
      const Expanded(child: Divider(indent: 12)),
    ]);
  }
}

class _EmptySection extends StatelessWidget {
  final String label;
  const _EmptySection({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(label,
          style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  final ChoreInstance instance;
  const _TaskCard({required this.instance});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBonus = instance.choreType == ChoreType.bonus;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isBonus ? Icons.star_rounded : Icons.task_alt_rounded,
          color: isBonus ? Colors.amber[700] : Colors.green,
          size: 30,
        ),
        title: Text(instance.choreName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          ScoreChip(score: instance.choreScore),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => _claim(ref, context),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36)),
            child: const Text('קח'),
          ),
        ]),
      ),
    );
  }

  Future<void> _claim(WidgetRef ref, BuildContext context) async {
    final user = ref.read(currentFamilyUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref
          .read(instanceRepositoryProvider)
          .claimInstance(user.familyId, instance.id, user.email);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('נרשמת למשימה "${instance.choreName}" ✓')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatRow(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}

// ── Tab 1: My chores ──────────────────────────────────────────────────────────

class _MyChoresTab extends ConsumerWidget {
  const _MyChoresTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myAsync = ref.watch(myInstancesProvider);

    return myAsync.when(
      loading: () => const AppLoading(),
      error: (e, _) => Center(child: Text('שגיאה: $e')),
      data: (instances) {
        if (instances.isEmpty) {
          return const Center(
            child: Text('טרם נרשמת למשימות השבוע.\nלחץ על "הבית" כדי להתחיל.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
          );
        }
        final active =
            instances.where((i) => i.status == InstanceStatus.claimed).toList();
        final pending = instances
            .where((i) => i.status == InstanceStatus.completed)
            .toList();
        final approved =
            instances.where((i) => i.status == InstanceStatus.approved).toList();

        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            if (active.isNotEmpty) ...[
              _sectionHeader('בביצוע'),
              ...active.map((i) => _MyChoreCard(instance: i)),
            ],
            if (pending.isNotEmpty) ...[
              _sectionHeader('ממתין לאישור הורה'),
              ...pending.map((i) => _MyChoreCard(instance: i)),
            ],
            if (approved.isNotEmpty) ...[
              _sectionHeader('אושר ✓'),
              ...approved.map((i) => _MyChoreCard(instance: i)),
            ],
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey)),
      );
}

class _MyChoreCard extends ConsumerWidget {
  final ChoreInstance instance;
  const _MyChoreCard({required this.instance});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isClaimed = instance.status == InstanceStatus.claimed;
    final isApproved = instance.status == InstanceStatus.approved;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: Icon(
          isApproved
              ? Icons.verified_rounded
              : isClaimed
                  ? Icons.hourglass_top_rounded
                  : Icons.pending_actions_rounded,
          color: isApproved
              ? Colors.green
              : isClaimed
                  ? Colors.orange
                  : Colors.blue,
          size: 30,
        ),
        title: Text(instance.choreName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          ScoreChip(
              score: instance.choreScore,
              color: isApproved ? Colors.green : null),
          if (isClaimed) ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _markDone(ref, context),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: const Text('בוצע!'),
            ),
          ],
        ]),
      ),
    );
  }

  Future<void> _markDone(WidgetRef ref, BuildContext context) async {
    final user = ref.read(currentFamilyUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref
          .read(instanceRepositoryProvider)
          .markCompleted(user.familyId, instance.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('מעולה! ממתין לאישור הורה.')),
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
