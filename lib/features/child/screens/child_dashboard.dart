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

// 0=Sun … 6=Sat
const _dayAbbr = ['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳', 'ש׳'];

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// Midnight of the calendar day containing [dt].
DateTime _dayMidnight(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

// The calendar date for weekday offset [dayIndex] (0=Sun) within [weekStart].
DateTime _weekDay(DateTime weekStart, int dayIndex) =>
    DateTime(weekStart.year, weekStart.month, weekStart.day + dayIndex);

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureBalance());
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

// ── Tab 0: Home ───────────────────────────────────────────────────────────────

class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(myBalanceStreamProvider);
    final chores = ref.watch(visibleChoresProvider);
    final weekInstancesAsync = ref.watch(weekAllInstancesProvider);
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
        final progress = quota > 0 ? (earned / quota).clamp(0.0, 1.0) : 0.0;
        final colorScheme = Theme.of(context).colorScheme;
        final weekInstances = weekInstancesAsync.valueOrNull ?? [];
        final childEmail = user?.email ?? '';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Weekly goal card ─────────────────────────────────────────────
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

              // ── Chore cards ──────────────────────────────────────────────────
              const SizedBox(height: 28),
              const _SectionHeader(title: 'משימות זמינות'),
              const SizedBox(height: 8),
              if (weekInstancesAsync.isLoading)
                const Center(child: CircularProgressIndicator())
              else if (chores.isEmpty)
                _EmptySection(label: 'אין משימות זמינות השבוע')
              else
                ...chores.map((chore) => _ChoreCard(
                      chore: chore,
                      weekInstances: weekInstances,
                      childEmail: childEmail,
                      weekStart: weekStart,
                    )),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

// A card for a single chore showing availability + child's own registrations.
class _ChoreCard extends StatelessWidget {
  final Chore chore;
  final List<ChoreInstance> weekInstances;
  final String childEmail;
  final DateTime weekStart;

  const _ChoreCard({
    required this.chore,
    required this.weekInstances,
    required this.childEmail,
    required this.weekStart,
  });

  @override
  Widget build(BuildContext context) {
    final activeForChore = weekInstances
        .where((i) => i.choreId == chore.id && i.isActiveSlot)
        .toList();
    final myActive = activeForChore
        .where((i) => i.registeredBy == childEmail)
        .toList();
    final usedSlots = activeForChore.length;
    final remaining = chore.availablePerWeek - usedSlots;

    final myDays = myActive
        .map((i) => '${_dayAbbr[i.registeredDay.weekday % 7]} ${i.registeredDay.day}/${i.registeredDay.month}')
        .join(', ');

    final subtitle = myDays.isNotEmpty
        ? 'שלי: $myDays'
        : remaining > 0
            ? 'נשארו $remaining מקומות'
            : 'אין מקומות פנויים';

    final isPoolFull = remaining <= 0 && myActive.isEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          chore.type == ChoreType.weeklyPool
              ? Icons.repeat_rounded
              : Icons.calendar_today_rounded,
          color: isPoolFull
              ? Colors.grey
              : Theme.of(context).colorScheme.primary,
          size: 28,
        ),
        title: Text(chore.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: ScoreChip(score: chore.score),
        onTap: isPoolFull
            ? null
            : () => _showDayPicker(context),
      ),
    );
  }

  void _showDayPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DayPickerSheet(
        chore: chore,
        weekInstances: weekInstances,
        childEmail: childEmail,
        weekStart: weekStart,
      ),
    );
  }
}

// Bottom sheet for selecting (or unselecting) registration days.
class _DayPickerSheet extends ConsumerWidget {
  final Chore chore;
  final List<ChoreInstance> weekInstances;
  final String childEmail;
  final DateTime weekStart;

  const _DayPickerSheet({
    required this.chore,
    required this.weekInstances,
    required this.childEmail,
    required this.weekStart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = _dayMidnight(DateTime.now());
    final activeForChore = weekInstances
        .where((i) => i.choreId == chore.id && i.isActiveSlot)
        .toList();
    final usedSlots = activeForChore.length;
    final remaining = chore.availablePerWeek - usedSlots;

    // Which day indices to show
    final List<int> dayIndices = chore.type == ChoreType.weeklyPool
        ? List.generate(7, (i) => i)
        : chore.scheduledDays;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text(chore.name,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            remaining > 0
                ? 'נשארו $remaining מקומות פנויים'
                : 'כל המקומות תפוסים',
            style: TextStyle(
                fontSize: 13,
                color: remaining > 0 ? Colors.green[700] : Colors.red[700]),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: dayIndices.map((dayIdx) {
              final day = _weekDay(weekStart, dayIdx);
              final dayMidnight = _dayMidnight(day);
              final isPast = dayMidnight.isBefore(today);
              final myInstance = activeForChore
                  .where((i) =>
                      i.registeredBy == childEmail &&
                      _sameDay(i.registeredDay, dayMidnight))
                  .firstOrNull;
              final isMine = myInstance != null;
              final takenByOther = activeForChore.any((i) =>
                  i.registeredBy != childEmail &&
                  _sameDay(i.registeredDay, dayMidnight));
              final isPoolFull = remaining <= 0 && !isMine;
              final isDisabled = isPast || takenByOther || isPoolFull;

              final label =
                  '${_dayAbbr[dayIdx]}\n${day.day}/${day.month}';

              if (isMine) {
                return _DayChip(
                  label: label,
                  state: _ChipState.mine,
                  onTap: () => _unregister(ref, context, myInstance),
                );
              }
              return _DayChip(
                label: label,
                state: isDisabled
                    ? (takenByOther
                        ? _ChipState.taken
                        : _ChipState.disabled)
                    : _ChipState.available,
                onTap: isDisabled
                    ? null
                    : () => _register(ref, context, dayMidnight),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          if (chore.type == ChoreType.weeklyPool)
            Text(
              'לחץ על יום כדי להירשם • לחץ שוב על יום שלך כדי לבטל',
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Future<void> _register(
      WidgetRef ref, BuildContext context, DateTime day) async {
    final user = ref.read(currentFamilyUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref
          .read(instanceRepositoryProvider)
          .registerForDay(user.familyId, chore, day, user.email, weekStart);
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'נרשמת ל"${chore.name}" ב-${day.day}/${day.month} ✓')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _unregister(
      WidgetRef ref, BuildContext context, ChoreInstance instance) async {
    final user = ref.read(currentFamilyUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref
          .read(instanceRepositoryProvider)
          .unregister(user.familyId, instance.id);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('שגיאה: $e')));
      }
    }
  }
}

enum _ChipState { available, mine, taken, disabled }

class _DayChip extends StatelessWidget {
  final String label;
  final _ChipState state;
  final VoidCallback? onTap;

  const _DayChip({required this.label, required this.state, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Color bg;
    Color fg;
    Color border;
    bool showCheck = false;

    switch (state) {
      case _ChipState.mine:
        bg = colorScheme.primary;
        fg = colorScheme.onPrimary;
        border = colorScheme.primary;
        showCheck = true;
      case _ChipState.available:
        bg = colorScheme.surface;
        fg = colorScheme.onSurface;
        border = colorScheme.outline;
      case _ChipState.taken:
        bg = colorScheme.surfaceContainerHighest;
        fg = colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
        border = colorScheme.outlineVariant;
      case _ChipState.disabled:
        bg = colorScheme.surfaceContainerHighest;
        fg = colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
        border = colorScheme.outlineVariant;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 70,
        height: 64,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: fg),
              ),
            ),
            if (showCheck)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.check_circle, size: 14, color: fg),
              ),
            if (state == _ChipState.taken)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.lock_outline, size: 13, color: fg),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

// ── Tab 1: My Chores (4 sections) ────────────────────────────────────────────

class _MyChoresTab extends ConsumerWidget {
  const _MyChoresTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myAsync = ref.watch(myRegistrationsProvider);

    return myAsync.when(
      loading: () => const AppLoading(),
      error: (e, _) => Center(child: Text('שגיאה: $e')),
      data: (instances) {
        final today = _dayMidnight(DateTime.now());

        // Partition into the 4 visible sections (silently drop expired & cancelled/rejected)
        final todayList = instances
            .where((i) =>
                i.status == InstanceStatus.registered &&
                _sameDay(i.registeredDay, today))
            .toList();
        final upcomingList = instances
            .where((i) =>
                i.status == InstanceStatus.registered &&
                i.registeredDay.isAfter(today))
            .toList()
          ..sort((a, b) => a.registeredDay.compareTo(b.registeredDay));
        final pendingList = instances
            .where((i) => i.status == InstanceStatus.completed)
            .toList();
        final doneList = instances
            .where((i) => i.status == InstanceStatus.approved)
            .toList();

        final hasAnything = todayList.isNotEmpty ||
            upcomingList.isNotEmpty ||
            pendingList.isNotEmpty ||
            doneList.isNotEmpty;

        if (!hasAnything) {
          return const Center(
            child: Text('טרם נרשמת למשימות השבוע.\nלחץ על "הבית" כדי להתחיל.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            if (todayList.isNotEmpty) ...[
              _sectionLabel('היום'),
              ...todayList.map((i) =>
                  _MyChoreCard(instance: i, showDoneButton: true)),
            ],
            if (upcomingList.isNotEmpty) ...[
              _sectionLabel('הקרוב'),
              ...upcomingList.map((i) =>
                  _MyChoreCard(instance: i, showUnregisterButton: true)),
            ],
            if (pendingList.isNotEmpty) ...[
              _sectionLabel('ממתין לאישור הורה'),
              ...pendingList.map((i) => _MyChoreCard(instance: i)),
            ],
            if (doneList.isNotEmpty) ...[
              _sectionLabel('הושלם ✓'),
              ...doneList.map((i) => _MyChoreCard(instance: i)),
            ],
          ],
        );
      },
    );
  }

  Widget _sectionLabel(String title) => Padding(
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
  final bool showDoneButton;
  final bool showUnregisterButton;

  const _MyChoreCard({
    required this.instance,
    this.showDoneButton = false,
    this.showUnregisterButton = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isApproved = instance.status == InstanceStatus.approved;
    final isPending = instance.status == InstanceStatus.completed;

    IconData icon;
    Color iconColor;
    if (isApproved) {
      icon = Icons.verified_rounded;
      iconColor = Colors.green;
    } else if (isPending) {
      icon = Icons.pending_actions_rounded;
      iconColor = Colors.blue;
    } else {
      icon = Icons.hourglass_top_rounded;
      iconColor = Colors.orange;
    }

    final dayLabel =
        '${instance.registeredDay.day}/${instance.registeredDay.month}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: Icon(icon, color: iconColor, size: 30),
        title: Text(instance.choreName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(dayLabel),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          ScoreChip(
              score: instance.choreScore,
              color: isApproved ? Colors.green : null),
          if (showDoneButton) ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _markDone(ref, context),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: const Text('בוצע!'),
            ),
          ],
          if (showUnregisterButton) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _unregister(ref, context),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  foregroundColor: Colors.red),
              child: const Text('בטל'),
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

  Future<void> _unregister(WidgetRef ref, BuildContext context) async {
    final user = ref.read(currentFamilyUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref
          .read(instanceRepositoryProvider)
          .unregister(user.familyId, instance.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('שגיאה: $e')));
      }
    }
  }
}
