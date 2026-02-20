import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/user_repository.dart';
import '../../domain/models/app_user.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  // Toggle this for testing:
  return const MockUserRepository(pretendAdmin: true);
});

/// Global current user (fetches on app start, cached by Riverpod).
final currentUserProvider = FutureProvider<AppUser>((ref) async {
  final repo = ref.read(userRepositoryProvider);
  return repo.getCurrentUser();
});
