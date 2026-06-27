import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../parent/providers/parent_providers.dart';
import '../../shared/models/chore.dart';

// 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat
const _dayLabels = ['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳', 'ש׳'];

class ChoreFormScreen extends ConsumerStatefulWidget {
  final Chore? existing;
  const ChoreFormScreen({super.key, this.existing});

  @override
  ConsumerState<ChoreFormScreen> createState() => _ChoreFormScreenState();
}

class _ChoreFormScreenState extends ConsumerState<ChoreFormScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _scoreCtrl = TextEditingController();
  final _availableCtrl = TextEditingController();
  ChoreType _type = ChoreType.weeklyPool;
  // specificDay: actual calendar dates selected from the rolling 7-day window.
  List<DateTime> _selectedDates = [];
  bool _saving = false;

  // The next 7 calendar days (today through today+6).
  late final List<DateTime> _nextSevenDays;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    _nextSevenDays =
        List.generate(7, (i) => todayMidnight.add(Duration(days: i)));

    final c = widget.existing;
    if (c != null) {
      _nameCtrl.text = c.name;
      _descCtrl.text = c.description;
      _scoreCtrl.text = c.score.toString();
      _availableCtrl.text = c.availablePerWeek.toString();
      _type = c.type;
      // Keep only dates that are still in the future (>= today) for editing.
      _selectedDates = c.scheduledDates
          .where((d) => !d.isBefore(todayMidnight))
          .toList();
    } else {
      _scoreCtrl.text = '10';
      _availableCtrl.text = '1';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _scoreCtrl.dispose();
    _availableCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    if (_type == ChoreType.specificDay && _selectedDates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש לבחור לפחות יום אחד למשימה ביום ספציפי')),
      );
      return;
    }

    final score = int.tryParse(_scoreCtrl.text) ?? 10;

    int availablePerWeek;
    List<DateTime> scheduledDates;

    if (_type == ChoreType.weeklyPool) {
      availablePerWeek =
          (int.tryParse(_availableCtrl.text) ?? 1).clamp(1, 7);
      scheduledDates = [];
    } else {
      scheduledDates = List<DateTime>.from(_selectedDates)..sort();
      availablePerWeek = scheduledDates.length;
    }

    setState(() => _saving = true);
    try {
      final user = ref.read(currentFamilyUserProvider).valueOrNull!;
      final choreRepo = ref.read(choreRepositoryProvider);

      if (widget.existing == null) {
        await choreRepo.createChore(
          familyId: user.familyId,
          name: name,
          description: _descCtrl.text.trim(),
          score: score,
          type: _type,
          availablePerWeek: availablePerWeek,
          scheduledDates: scheduledDates,
          createdBy: user.email,
        );
      } else {
        await choreRepo.updateChore(Chore(
          id: widget.existing!.id,
          familyId: user.familyId,
          name: name,
          description: _descCtrl.text.trim(),
          score: score,
          type: _type,
          availablePerWeek: availablePerWeek,
          scheduledDates: scheduledDates,
          isActive: true,
          createdBy: widget.existing!.createdBy,
          createdAt: widget.existing!.createdAt,
        ));
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('שגיאה בשמירה: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'ערוך משימה' : 'משימה חדשה')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'שם המשימה *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                  labelText: 'תיאור (אופציונלי)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _scoreCtrl,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                  labelText: 'ניקוד', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            const Text('סוג משימה:', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            SegmentedButton<ChoreType>(
              segments: const [
                ButtonSegment(
                    value: ChoreType.weeklyPool,
                    label: Text('שבועי'),
                    icon: Icon(Icons.repeat_rounded)),
                ButtonSegment(
                    value: ChoreType.specificDay,
                    label: Text('יום ספציפי'),
                    icon: Icon(Icons.calendar_today_rounded)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            if (_type == ChoreType.weeklyPool) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _availableCtrl,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText: 'כמה פעמים בשבוע (1–7)',
                    border: OutlineInputBorder()),
              ),
            ],
            if (_type == ChoreType.specificDay) ...[
              const SizedBox(height: 16),
              const Text('ימים זמינים (7 ימים הקרובים):',
                  style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _nextSevenDays.map((date) {
                  final selected = _selectedDates
                      .any((d) => _sameDay(d, date));
                  final label =
                      '${_dayLabels[date.weekday % 7]} ${date.day}/${date.month}';
                  return FilterChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (on) => setState(() {
                      if (on) {
                        _selectedDates.add(date);
                        _selectedDates.sort();
                      } else {
                        _selectedDates
                            .removeWhere((d) => _sameDay(d, date));
                      }
                    }),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 28),
            if (_saving)
              const Center(child: CircularProgressIndicator())
            else
              FilledButton(onPressed: _save, child: const Text('שמור')),
          ],
        ),
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
