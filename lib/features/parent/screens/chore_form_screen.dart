import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/week_utils.dart';
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
  final _freqCtrl = TextEditingController();
  ChoreType _type = ChoreType.weekly;
  List<int> _selectedDays = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    if (c != null) {
      _nameCtrl.text = c.name;
      _descCtrl.text = c.description;
      _scoreCtrl.text = c.score.toString();
      _freqCtrl.text = c.frequency.toString();
      _type = c.type;
      _selectedDays = List<int>.from(c.days);
    } else {
      _scoreCtrl.text = '10';
      _freqCtrl.text = '1';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _scoreCtrl.dispose();
    _freqCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    if (_type == ChoreType.daily && _selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש לבחור לפחות יום אחד למשימה יומית')),
      );
      return;
    }

    final score = int.tryParse(_scoreCtrl.text) ?? 10;
    final freq = _type == ChoreType.weekly
        ? (int.tryParse(_freqCtrl.text) ?? 1)
        : _selectedDays.length;
    final days = _type == ChoreType.daily ? List<int>.from(_selectedDays) : <int>[];

    setState(() => _saving = true);
    try {
      final user = ref.read(currentFamilyUserProvider).valueOrNull!;
      final choreRepo = ref.read(choreRepositoryProvider);
      final instanceRepo = ref.read(instanceRepositoryProvider);

      if (widget.existing == null) {
        final chore = await choreRepo.createChore(
          familyId: user.familyId,
          name: name,
          description: _descCtrl.text.trim(),
          score: score,
          type: _type,
          frequency: freq,
          days: days,
          createdBy: user.email,
        );
        final weekStart = getWeekStart();
        switch (_type) {
          case ChoreType.daily:
            await instanceRepo.createDailyInstancesForWeek(
                user.familyId, chore, weekStart);
          case ChoreType.weekly:
            await instanceRepo.createWeeklyInstancesForWeek(
                user.familyId, chore, weekStart);
          case ChoreType.bonus:
            await instanceRepo.createBonusInstance(
                user.familyId, chore, weekStart);
        }
      } else {
        await choreRepo.updateChore(Chore(
          id: widget.existing!.id,
          familyId: user.familyId,
          name: name,
          description: _descCtrl.text.trim(),
          score: score,
          type: _type,
          frequency: freq,
          days: days,
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
                    value: ChoreType.daily,
                    label: Text('יומי'),
                    icon: Icon(Icons.calendar_today_rounded)),
                ButtonSegment(
                    value: ChoreType.weekly,
                    label: Text('שבועי'),
                    icon: Icon(Icons.repeat_rounded)),
                ButtonSegment(
                    value: ChoreType.bonus,
                    label: Text('בונוס'),
                    icon: Icon(Icons.star_rounded)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            if (_type == ChoreType.daily) ...[
              const SizedBox(height: 16),
              const Text('ימים בשבוע:', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: List.generate(7, (day) {
                  final selected = _selectedDays.contains(day);
                  return FilterChip(
                    label: Text(_dayLabels[day]),
                    selected: selected,
                    onSelected: (on) => setState(() {
                      if (on) {
                        _selectedDays.add(day);
                        _selectedDays.sort();
                      } else {
                        _selectedDays.remove(day);
                      }
                    }),
                  );
                }),
              ),
            ],
            if (_type == ChoreType.weekly) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _freqCtrl,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText: 'כמה פעמים בשבוע',
                    border: OutlineInputBorder()),
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
