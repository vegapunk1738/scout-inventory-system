import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scout_stock/data/repositories/auth_repository.dart' show AuthException;
import 'package:scout_stock/state/providers/auth_providers.dart';

/// Wraps the app and keeps the auth session in sync with the backend.
///
/// Catches two categories of external changes:
///   1. Another admin changed my role or name → new JWT carries updated data,
///      GoRouter redirect reacts automatically.
///   2. Another admin deleted my account → refresh returns 401 → logout.
///
/// Triggers:
///   • App resumed from background (covers mobile lock/unlock, tab switch on web).
///   • Periodic heartbeat every [_kHeartbeatInterval] while authenticated.
///
/// Place this directly inside [MaterialApp.router]'s builder:
///
/// ```dart
/// builder: (context, child) => SessionGuard(child: child!),
/// ```
class SessionGuard extends ConsumerStatefulWidget {
  const SessionGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends ConsumerState<SessionGuard> {
  /// How often to silently refresh the session while the app is in the
  /// foreground. 5 minutes is a good balance — frequent enough to catch
  /// changes within a camp session, rare enough to be invisible.
  static const _kHeartbeatInterval = Duration(minutes: 5);

  late final AppLifecycleListener _lifecycleListener;
  Timer? _heartbeat;

  @override
  void initState() {
    super.initState();

    _lifecycleListener = AppLifecycleListener(
      onResume: _onAppResumed,
      // On web, fires when the tab becomes visible again.
      // On mobile, fires when the app comes back from background.
    );

    _startHeartbeat();
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _heartbeat?.cancel();
    super.dispose();
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_kHeartbeatInterval, (_) => _refreshSession());
  }

  void _onAppResumed() {
    _refreshSession();
    // Reset the timer so we don't double-fire right after a resume.
    _startHeartbeat();
  }

  Future<void> _refreshSession() async {
    // Only refresh if there's an active session.
    final isAuth = ref.read(isAuthenticatedProvider);
    if (!isAuth) return;

    try {
      await ref.read(authControllerProvider.notifier).refreshSession();
    } on AuthException {
      // AuthException means the backend actively rejected us:
      // 401 (user deleted, token invalid, etc.)
      // The repo already cleared stored prefs on 401 — update the
      // controller state so GoRouter redirects to login.
      await ref.read(authControllerProvider.notifier).logout();
    } catch (_) {
      // Network error, timeout, 500 — swallow silently.
      // The current JWT is still valid locally; the user will get a
      // proper error on their next explicit action.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}