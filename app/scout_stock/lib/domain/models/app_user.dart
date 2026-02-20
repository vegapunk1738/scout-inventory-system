import '../enums/user_role.dart';

/// Matches backend requirements:
/// - name
/// - identifier (email/username/scout ID)
/// - role (explicit, not inferred)
/// Also includes an `id` for DB primary key.
class AppUser {
  final String id;
  final String name;
  final String identifier;
  final UserRole role;

  const AppUser({
    required this.id,
    required this.name,
    required this.identifier,
    required this.role,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      name: json['name'] as String,
      identifier: json['identifier'] as String,
      role: UserRole.fromString(json['role'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'identifier': identifier,
    'role': role.toJson(),
  };
}
