import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/family_setup_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/no_family_screen.dart';
import '../../features/child/screens/child_dashboard.dart';
import '../../features/parent/screens/parent_dashboard.dart';
import '../../features/shared/models/family_user.dart';
import '../../features/shared/widgets/app_loading.dart';

// ── Router notifier that refreshes GoRouter on auth/user state changes ────────

class _RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  _RouterNotifier(this._ref) {
    _ref.listen(authStateProvider, (prev, next) => notifyListeners());
    _ref.listen(currentFamilyUserProvider, (prev, next) => notifyListeners());
  }

  String? redirect(BuildContext context, GoRouterState state) {
    final authAsync = _ref.read(authStateProvider);
    final userAsync = _ref.read(currentFamilyUserProvider);

    // Still loading — don't redirect
    if (authAsync.isLoading) return null;
    if (authAsync.valueOrNull != null && userAsync.isLoading) return null;

    final isLoggedIn = authAsync.valueOrNull != null;
    final familyUser = userAsync.valueOrNull;

    final loc = state.matchedLocation;

    if (!isLoggedIn) {
      return loc == '/login' ? null : '/login';
    }

    // Logged in but not in any family
    if (familyUser == null) {
      if (loc == '/no-family' || loc == '/setup') return null;
      return '/no-family';
    }

    // Logged in and in a family — leave auth screens
    if (loc == '/login' || loc == '/no-family' || loc == '/setup') {
      return familyUser.role == UserRole.parent ? '/parent' : '/child';
    }

    // Role guard: children can't access /parent routes and vice versa
    if (familyUser.role == UserRole.child && loc.startsWith('/parent')) {
      return '/child';
    }
    if (familyUser.role == UserRole.parent && loc.startsWith('/child')) {
      return '/parent';
    }

    return null;
  }
}

// ── Loading screen shown during auth resolution ───────────────────────────────

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(body: AppLoading());
}

// ── Provider ──────────────────────────────────────────────────────────────────

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);

  return GoRouter(
    refreshListenable: notifier,
    redirect: notifier.redirect,
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/no-family',
        builder: (context, state) => const NoFamilyScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const FamilySetupScreen(),
      ),
      GoRoute(
        path: '/parent',
        builder: (context, state) => const ParentDashboard(),
      ),
      GoRoute(
        path: '/child',
        builder: (context, state) => const ChildDashboard(),
      ),
    ],
    errorBuilder: (context, state) => const _SplashScreen(),
  );
});
