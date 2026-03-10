import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/auth_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/auth_session.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override sharedPreferencesProvider in main().');
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return HttpAuthRepository(prefs);
});

class AuthController extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() async {
    final repo = ref.read(authRepositoryProvider);
    // restoreSession() internally tries to refresh the token
    return repo.restoreSession();
  }

  Future<bool> login({
    required String identifier,
    required String password,
  }) async {
    final repo = ref.read(authRepositoryProvider);

    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => repo.login(identifier: identifier, password: password),
    );

    return state.hasValue && state.value != null;
  }

  Future<void> logout() async {
    final repo = ref.read(authRepositoryProvider);
    await repo.logout();
    state = const AsyncData(null);
  }

  /// Re-fetches a fresh JWT from the backend (picks up role/name changes).
  /// Updates the local session state so GoRouter and all watchers react.
  Future<void> refreshSession() async {
    final repo = ref.read(authRepositoryProvider);
    final refreshed = await repo.refresh();
    state = AsyncData(refreshed);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

final currentUserProvider = Provider<AppUser?>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth.asData?.value?.user;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth.asData?.value != null;
});

final accessTokenProvider = Provider<String?>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth.asData?.value?.token;
});