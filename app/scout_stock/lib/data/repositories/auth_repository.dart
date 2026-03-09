import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../domain/models/auth_session.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class AuthRepository {
  Future<AuthSession?> restoreSession();
  Future<AuthSession> login({
    required String identifier,
    required String password,
  });
  Future<AuthSession> refresh();
  Future<void> logout();
}

class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._prefs);

  static const _sessionKey = 'scout_stock_auth_session';

  final SharedPreferences _prefs;

  @override
  Future<AuthSession?> restoreSession() async {
    final raw = _prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final session = AuthSession.fromJson(decoded);

      // Try to refresh the token on restore
      try {
        return await _refreshWithToken(session.token);
      } catch (_) {
        // Refresh failed (token invalid, user deleted, etc.)
        // Return the cached session — the app can still try to use it
        // or the next API call will fail and trigger logout
        return session;
      }
    } catch (_) {
      await _prefs.remove(_sessionKey);
      return null;
    }
  }

  @override
  Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    const client = ApiClient();

    try {
      final body = await client.post('/auth/login', body: {
        'identifier': identifier,
        'password': password,
      });

      final session = AuthSession.fromJson(body);
      await _saveSession(session);
      return session;
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
  }

  @override
  Future<AuthSession> refresh() async {
    final raw = _prefs.getString(_sessionKey);
    if (raw == null) throw const AuthException('No session to refresh');

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final currentToken = decoded['token'] as String;

    return _refreshWithToken(currentToken);
  }

  Future<AuthSession> _refreshWithToken(String token) async {
    final client = ApiClient(token: token);

    try {
      final body = await client.post('/auth/refresh');
      final session = AuthSession.fromJson(body);
      await _saveSession(session);
      return session;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        // Token is truly invalid — clear stored session
        await _prefs.remove(_sessionKey);
      }
      throw AuthException(e.message);
    }
  }

  Future<void> _saveSession(AuthSession session) async {
    await _prefs.setString(_sessionKey, jsonEncode(session.toJson()));
  }

  @override
  Future<void> logout() async {
    await _prefs.remove(_sessionKey);
  }
}