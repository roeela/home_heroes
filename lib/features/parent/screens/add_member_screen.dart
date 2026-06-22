import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../shared/models/family_user.dart';

class AddMemberScreen extends ConsumerStatefulWidget {
  const AddMemberScreen({super.key});

  @override
  ConsumerState<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends ConsumerState<AddMemberScreen> {
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _quotaCtrl = TextEditingController(text: '50');
  UserRole _role = UserRole.child;
  bool _saving = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _quotaCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final name = _nameCtrl.text.trim();
    if (email.isEmpty || name.isEmpty) return;

    setState(() => _saving = true);
    try {
      final user = ref.read(currentFamilyUserProvider).valueOrNull!;
      final userRepo = ref.read(userRepositoryProvider);

      final member = FamilyUser(
        docId: email,
        familyId: user.familyId,
        displayName: name,
        email: email,
        role: _role,
        weeklyQuota: _role == UserRole.child
            ? (int.tryParse(_quotaCtrl.text) ?? 50)
            : 0,
        isPrimary: false,
        status: UserStatus.pending,
        isActive: true,
      );
      await userRepo.createUser(member);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('שגיאה בהוספת חבר: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('הוסף בן משפחה')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'שם *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'כתובת Gmail *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            const Text('תפקיד:', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            SegmentedButton<UserRole>(
              segments: const [
                ButtonSegment(
                    value: UserRole.child,
                    label: Text('ילד/ה'),
                    icon: Icon(Icons.child_care)),
                ButtonSegment(
                    value: UserRole.parent,
                    label: Text('הורה'),
                    icon: Icon(Icons.supervisor_account)),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            if (_role == UserRole.child) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _quotaCtrl,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText: 'מכסה שבועית (נקודות)',
                    border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 28),
            if (_saving)
              const Center(child: CircularProgressIndicator())
            else
              FilledButton(onPressed: _add, child: const Text('הוסף')),
          ],
        ),
      ),
    );
  }
}
