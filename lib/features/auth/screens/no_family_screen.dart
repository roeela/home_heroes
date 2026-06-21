import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/providers/auth_provider.dart';

class NoFamilyScreen extends ConsumerWidget {
  const NoFamilyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.no_accounts_rounded,
                    size: 80, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 24),
                const Text(
                  'לא נמצאה משפחה',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'כתובת האימייל שלך אינה מוכרת במערכת.\n'
                  'בקש מהוריך להוסיף אותך, או צור משפחה חדשה.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 36),
                FilledButton.icon(
                  onPressed: () => context.go('/setup'),
                  icon: const Icon(Icons.add_home_rounded),
                  label: const Text('צור משפחה חדשה'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => signOut(ref),
                  child: const Text('יציאה'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
