import '../enums/user_role.dart';

class AppUser {
  final String id;
  final String name;
  final String scoutId;
  final UserRole role;

  const AppUser({
    required this.id,
    required this.name,
    required this.scoutId,
    required this.role,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      name: json['full_name'] as String,
      scoutId: json['scout_id'] as String,
      role: UserRole.fromString(json['role'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': name,
    'scout_id': scoutId,
    'role': role.toJson(),
  };
}
