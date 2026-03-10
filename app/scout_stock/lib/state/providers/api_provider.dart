import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scout_stock/data/api/api_client.dart';
import 'package:scout_stock/state/providers/auth_providers.dart';

/// Provides an authenticated [ApiClient] bound to the current session JWT.
/// Returns `null` when no session is active (user not logged in).
final apiClientProvider = Provider<ApiClient?>((ref) {
  final session = ref.watch(authControllerProvider).asData?.value;
  if (session == null) return null;

  return ApiClient(token: session.token);
});