import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:scout_stock/data/api/env_config.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException({required this.statusCode, required this.message});

  bool get isConflict => statusCode == 409;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

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

    // Backend may use 'error' (string), 'message' (string), or Zod's
    // { error: { issues: [...] } } format. Extract the best human-readable
    // message from whatever shape we get.
    throw ApiException(
      statusCode: response.statusCode,
      message: _extractErrorMessage(body),
    );
  }

  /// Tries several common shapes to find a usable error message.
  static String _extractErrorMessage(Map<String, dynamic> body) {
    // 1. { "error": "Some message" }  — your custom errors
    final errorVal = body['error'];
    if (errorVal is String && errorVal.isNotEmpty) return errorVal;

    // 2. { "message": "Some message" }  — Hono / Zod convention
    final messageVal = body['message'];
    if (messageVal is String && messageVal.isNotEmpty) return messageVal;

    // 3. { "error": { "issues": [ { "message": "..." }, ... ] } }  — raw Zod
    if (errorVal is Map) {
      final issues = errorVal['issues'];
      if (issues is List && issues.isNotEmpty) {
        final first = issues[0];
        if (first is Map && first['message'] is String) {
          return first['message'] as String;
        }
      }
    }

    return 'Something went wrong';
  }
}