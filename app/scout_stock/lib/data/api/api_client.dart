import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:scout_stock/data/api/env_config.dart';

// ── Field error record ───────────────────────────────────────────────────

class FieldError {
  const FieldError({required this.field, required this.message});

  /// Raw field name from the backend, e.g. `scout_id`.
  final String field;

  /// Human-readable message, already cleaned up.
  final String message;

  /// Pretty field label, e.g. `scout_id` → `Scout ID`.
  String get label => _prettyFieldName(field);

  static const _fieldLabels = <String, String>{
    'scout_id': 'Scout ID',
    'full_name': 'Full Name',
    'password': 'Password',
    'role': 'Role',
    'identifier': 'Identifier',
  };

  static String _prettyFieldName(String raw) {
    if (_fieldLabels.containsKey(raw)) return _fieldLabels[raw]!;
    // Fallback: snake_case → Title Case
    return raw
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

// ── API Exception ────────────────────────────────────────────────────────

class ApiException implements Exception {
  final int statusCode;
  final String message;

  /// Per-field validation errors. Supports multiple errors on the same field.
  final List<FieldError> fieldErrors;

  const ApiException({
    required this.statusCode,
    required this.message,
    this.fieldErrors = const [],
  });

  bool get isConflict => statusCode == 409;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isUnauthorized => statusCode == 401;
  bool get hasFieldErrors => fieldErrors.isNotEmpty;

  /// Single-string summary for contexts that can't show multiple toasts.
  String get displayMessage {
    if (fieldErrors.isEmpty) return message;
    final parts = fieldErrors.map((e) => '${e.label}: ${e.message}');
    return parts.join(' · ');
  }

  @override
  String toString() => displayMessage;
}

// ── API Client ───────────────────────────────────────────────────────────

class ApiClient {
  const ApiClient({this.token});

  final String? token;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Uri _uri(String path) => Uri.parse('${EnvConfig.apiBaseUrl}$path');

  Future<Map<String, dynamic>> get(String path) async {
    final response = await http.get(_uri(path), headers: _headers);
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await http.post(
      _uri(path),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await http.patch(
      _uri(path),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final response = await http.delete(_uri(path), headers: _headers);
    return _handleResponse(response);
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected response from server',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw _parseApiError(response.statusCode, body);
  }

  static ApiException _parseApiError(
    int statusCode,
    Map<String, dynamic> body,
  ) {
    // 1. Top-level message.
    final errorVal = body['error'];
    final messageVal = body['message'];

    final topMessage = (errorVal is String && errorVal.isNotEmpty)
        ? errorVal
        : (messageVal is String && messageVal.isNotEmpty)
        ? messageVal
        : 'Something went wrong';

    // 2. Collect field errors from `details` array.
    final fieldErrors = <FieldError>[];

    final details = body['details'];
    if (details is List) {
      for (final item in details) {
        if (item is Map) {
          final field = item['field'];
          final msg = item['message'];
          if (field is String && msg is String) {
            fieldErrors.add(FieldError(field: field, message: _humanize(msg)));
          }
        }
      }
    }

    // 3. Fallback: raw Zod shape { "error": { "issues": [...] } }.
    if (fieldErrors.isEmpty && errorVal is Map) {
      final issues = errorVal['issues'];
      if (issues is List) {
        for (final issue in issues) {
          if (issue is Map && issue['message'] is String) {
            final path = (issue['path'] as List?)?.join('.') ?? 'input';
            fieldErrors.add(
              FieldError(
                field: path,
                message: _humanize(issue['message'] as String),
              ),
            );
          }
        }
      }
    }

    return ApiException(
      statusCode: statusCode,
      message: topMessage,
      fieldErrors: fieldErrors,
    );
  }

  /// Rewrites common Zod/validator messages into plain English.
  static String _humanize(String raw) {
    // "Too small: expected string to have >=6 characters"
    final tooSmall = RegExp(
      r'Too small: expected string to have >=(\d+) characters',
    );
    final smallMatch = tooSmall.firstMatch(raw);
    if (smallMatch != null) {
      return 'Must be at least ${smallMatch.group(1)} characters';
    }

    // "Too big: expected string to have <=128 characters"
    final tooBig = RegExp(
      r'Too big: expected string to have <=(\d+) characters',
    );
    final bigMatch = tooBig.firstMatch(raw);
    if (bigMatch != null) {
      return 'Must be at most ${bigMatch.group(1)} characters';
    }

    // "String must contain at least 1 character(s)"
    final minChars = RegExp(r'String must contain at least (\d+) character');
    final minMatch = minChars.firstMatch(raw);
    if (minMatch != null) {
      final n = minMatch.group(1);
      return n == '1' ? 'Cannot be empty' : 'Must be at least $n characters';
    }

    // "Expected string, received number"
    if (raw.startsWith('Expected ')) {
      return 'Invalid format';
    }

    // "Invalid enum value. Expected 'admin' | 'scout', received '...'"
    if (raw.contains('Invalid enum value')) {
      return 'Invalid option';
    }

    return raw;
  }
}
