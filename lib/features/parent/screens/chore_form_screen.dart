import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/week_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../../parent/providers/parent_providers.dart';
import '../../shared/models/chore.dart';

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
  ChoreType _type = ChoreType.recurring;
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
    final score = int.tryParse(_scoreCtrl.text) ?? 10;
    final freq = int.tryParse(_freqCtrl.text) ?? 1;

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
          createdBy: user.email,
        );
        // For adhoc chores, immediately create one open instance this week
        if (_type == ChoreType.adhoc) {
          await instanceRepo.createAdhocInstance(
              user.familyId, chore, getWeekStart());
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
      appBar: AppBar(title: Text(isEdit ? 'ערוך תורנות' : 'תורנות חדשה')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'שם התורנות *', border: OutlineInputBorder()),
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
              decoration: const InputDecoration(
                  labelText: 'ניקוד', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            const Text('סוג תורנות:', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            SegmentedButton<ChoreType>(
              segments: const [
                ButtonSegment(
                    value: ChoreType.recurring,
                    label: Text('שבועי חוזר'),
                    icon: Icon(Icons.repeat)),
                ButtonSegment(
                    value: ChoreType.adhoc,
                    label: Text('חד-פעמי'),
                    icon: Icon(Icons.flash_on)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            if (_type == ChoreType.recurring) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _freqCtrl,
                keyboardType: TextInputType.number,
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
