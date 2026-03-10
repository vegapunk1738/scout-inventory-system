import '../enums/user_role.dart';

/// The scout_id of the seed super-admin from your backend's SEED_USERS[0].
/// Set this once to match your seed file. The frontend uses it to lock
/// edit/delete controls — the backend still enforces it independently.
const String kSuperAdminScoutId = '0001'; // ← match your SEED_USERS[0].scout_id

/// Represents a user record returned by the admin `GET /users` endpoint.
///
/// Distinct from [AppUser] (which models the JWT session payload).
class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.scoutId,
    required this.fullName,
    required this.role,
    required this.createdAt,
  });

  final String id;
  final String scoutId;
  final String fullName;
  final UserRole role;
  final String createdAt;

  /// `true` when this user is the seed super-admin.
  /// Derived from the constant — no backend field needed.
  bool get isSuperAdmin => scoutId == kSuperAdminScoutId;

  factory ManagedUser.fromJson(Map<String, dynamic> json) {
    return ManagedUser(
      id: json['id'] as String,
      scoutId: json['scout_id'] as String,
      fullName: json['full_name'] as String,
      role: UserRole.fromString(json['role'] as String),
      createdAt: json['created_at'] as String,
    );
  }

  ManagedUser copyWith({
    String? fullName,
    UserRole? role,
  }) {
    return ManagedUser(
      id: id,
      scoutId: scoutId,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      createdAt: createdAt,
    );
  }
}