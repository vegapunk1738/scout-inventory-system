import 'app_user.dart';

class AuthSession {
  final String token;
  final AppUser user;

  const AuthSession({required this.token, required this.user});

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      token: json['token'] as String,
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  /// For storing in SharedPreferences.
  Map<String, dynamic> toJson() => {'token': token, 'user': user.toJson()};
}
