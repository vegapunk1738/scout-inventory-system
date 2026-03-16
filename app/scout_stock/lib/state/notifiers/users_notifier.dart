import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scout_stock/data/api/api_client.dart';

import 'package:scout_stock/domain/models/managed_user.dart';
import 'package:scout_stock/presentation/widgets/resolve_borrowed_helper.dart';
import 'package:scout_stock/state/providers/api_provider.dart';

/// Manages the admin user list.
///
/// Lazy: `build()` fires `GET /users` only when first watched (i.e. when the
/// admin navigates to the Users tab). Mutations hit the API then patch local
/// state — no full refetch needed.
class UsersNotifier extends AsyncNotifier<List<ManagedUser>> {
  ApiClient get _api {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not authenticated');
    return client;
  }

  // ── Initial fetch ──────────────────────────────────────────────────────

  @override
  Future<List<ManagedUser>> build() async {
    final res = await _api.get('/users');
    final raw = (res['data'] as List).cast<Map<String, dynamic>>();
    final users = raw.map(ManagedUser.fromJson).toList()..sort(_byName);
    return users;
  }

  // ── Next available scout_id ────────────────────────────────────────────

  /// Fetches the next available scout_id from the backend.
  /// Returns a zero-padded string like "0003".
  Future<String> fetchNextScoutId() async {
    final res = await _api.get('/users/next-scout-id');
    return res['scout_id'] as String;
  }

  Future<List<UserBorrowedItemInfo>> fetchUserBorrowed(String scoutId) async {
    final response = await _api.get(
      '/users/by-scout-id/$scoutId/borrowed-items',
    );
    final items = (response['data'] as List)
        .map((e) => UserBorrowedItemInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    return items;
  }

  // ── Create ─────────────────────────────────────────────────────────────

  Future<ManagedUser> createUser({
    required String scoutId,
    required String fullName,
    required String password,
    required String role,
  }) async {
    final res = await _api.post(
      '/users',
      body: {
        'scout_id': scoutId,
        'full_name': fullName,
        'password': password,
        'role': role,
      },
    );

    final created = ManagedUser.fromJson(res['data'] as Map<String, dynamic>);
    state = AsyncData([...state.requireValue, created]..sort(_byName));
    return created;
  }

  // ── Update ─────────────────────────────────────────────────────────────

  Future<ManagedUser> updateUser(
    String scoutId, {
    String? fullName,
    String? role,
    String? password,
  }) async {
    // Frontend guard — backend also enforces this.
    final current = state.requireValue.firstWhere((u) => u.scoutId == scoutId);
    if (current.isSuperAdmin) {
      throw const ApiException(
        statusCode: 403,
        message: 'Super Admin cannot be modified',
      );
    }

    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName;
    if (role != null) body['role'] = role;
    if (password != null) body['password'] = password;

    if (body.isEmpty) throw ArgumentError('Nothing to update');

    final res = await _api.patch('/users/$scoutId', body: body);
    final updated = ManagedUser.fromJson(res['data'] as Map<String, dynamic>);

    final list = [...state.requireValue];
    final idx = list.indexWhere((u) => u.scoutId == scoutId);
    if (idx != -1) {
      list[idx] = updated;
      list.sort(_byName);
    }
    state = AsyncData(list);
    return updated;
  }

  // ── Delete ─────────────────────────────────────────────────────────────

  Future<void> deleteUser(String scoutId) async {
    // Frontend guard — backend also enforces this.
    final target = state.requireValue.firstWhere((u) => u.scoutId == scoutId);
    if (target.isSuperAdmin) {
      throw const ApiException(
        statusCode: 403,
        message: 'Super Admin cannot be deleted',
      );
    }

    await _api.delete('/users/$scoutId');

    final list = state.requireValue.where((u) => u.scoutId != scoutId).toList();
    state = AsyncData(list);
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  static int _byName(ManagedUser a, ManagedUser b) =>
      a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
}
