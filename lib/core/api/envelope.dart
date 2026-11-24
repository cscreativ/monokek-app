import 'package:dio/dio.dart';

/// Thrown when a controller answers `{status: "error", ...}`.
class ApiError implements Exception {
  ApiError(this.message, [this.errors]);
  final String message;
  final Object? errors;
  @override
  String toString() => message;
}

/// Unwraps the `{status, message, data, errors}` envelope every monokek-spring controller uses.
T unwrap<T>(Response<dynamic> response) {
  final body = response.data;
  if (body is Map<String, dynamic> && body['status'] == 'error') {
    throw ApiError(body['message'] as String? ?? 'Une erreur est survenue', body['errors']);
  }
  if (body is Map<String, dynamic> && body.containsKey('data') && body.containsKey('status')) {
    return body['data'] as T;
  }
  return body as T;
}

/// Un-enveloped responses (bare DTO, bare array) — kitchen and cash endpoints.
T unwrapRaw<T>(Response<dynamic> response) => response.data as T;

/// Spring `Page<T>`: returns `content`.
List<dynamic> unwrapRawPage(Response<dynamic> response) => (response.data as Map<String, dynamic>)['content'] as List<dynamic>;

/// Best human-readable message out of any thrown error.
String errorMessage(Object error, [String fallback = 'Impossible de joindre le serveur']) {
  if (error is ApiError) return error.message;
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String && (data['message'] as String).isNotEmpty) {
      return data['message'] as String;
    }
    if (error.response?.statusCode == 401) return 'Identifiants invalides ou session expirée';
    if (error.response?.statusCode == 403) return 'Action non autorisée';
  }
  return fallback;
}
