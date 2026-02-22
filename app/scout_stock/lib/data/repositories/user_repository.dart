import '../../domain/models/app_user.dart';
import '../../domain/enums/user_role.dart';

abstract class UserRepository {
  Future<AppUser> getCurrentUser();
}

class MockUserRepository implements UserRepository {
  const MockUserRepository({required this.pretendAdmin});

  final bool pretendAdmin;

  @override
  Future<AppUser> getCurrentUser() async {
    await Future.delayed(const Duration(milliseconds: 250));

    return AppUser(
      id: 'u_001',
      name: pretendAdmin ? 'Admin User' : 'Scout User',
      identifier: pretendAdmin ? 'admin@scouts-nde' : 'scout@scouts-nde',
      role: pretendAdmin ? UserRole.admin : UserRole.scout,
    );
  }
}
