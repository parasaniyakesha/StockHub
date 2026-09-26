import 'package:dio/dio.dart';

/// A failure that is safe to show to the user. Raw exceptions, stack traces and
/// server internals never reach the UI - only [message] and [fieldErrors].
class AppException implements Exception {
  AppException(this.message, {this.code = 'UNKNOWN', this.statusCode, Map<String, String>? fieldErrors})
      : fieldErrors = fieldErrors ?? const {};

  final String message;
  final String code;
  final int? statusCode;

  /// field path → message (from 422 VALIDATION_ERROR responses).
  final Map<String, String> fieldErrors;

  bool get isNetwork => code == 'NETWORK';
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isValidation => code == 'VALIDATION_ERROR';

  /// Message plus the first few field errors - for toasts where no form is shown.
  String get detailedMessage {
    if (fieldErrors.isEmpty) return message;
    final details = fieldErrors.values.take(3).join('\n');
    return '$message\n$details';
  }

  static const _genericMessage = 'Something went wrong. Please try again.';
  static const _networkMessage = 'Unable to reach the server. Check your connection and try again.';

  factory AppException.from(Object error) {
    if (error is AppException) return error;
    if (error is DioException) return AppException.fromDio(error);
    return AppException(_genericMessage);
  }

  factory AppException.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return AppException(_networkMessage, code: 'NETWORK');
      case DioExceptionType.cancel:
        return AppException('Request cancelled', code: 'CANCELLED');
      default:
        break;
    }
    final response = e.response;
    final status = response?.statusCode;
    final data = response?.data;
    if (data is Map && data['success'] == false) {
      final fields = <String, String>{};
      final errors = data['errors'];
      if (errors is List) {
        for (final err in errors) {
          if (err is Map && err['field'] != null) {
            fields.putIfAbsent(err['field'].toString(), () => err['message']?.toString() ?? 'Invalid value');
          }
        }
      }
      // Server messages are designed to be user-safe; 5xx are replaced by a generic text.
      final message = (status ?? 500) >= 500 ? _genericMessage : (data['message']?.toString() ?? _genericMessage);
      return AppException(message, code: data['code']?.toString() ?? 'UNKNOWN', statusCode: status, fieldErrors: fields);
    }
    if (status == 401) return AppException('Your session has expired. Please sign in again.', code: 'UNAUTHORIZED', statusCode: 401);
    if (status == 403) return AppException('You do not have permission to do this.', code: 'FORBIDDEN', statusCode: 403);
    if (status == 404) return AppException('The requested record was not found.', code: 'NOT_FOUND', statusCode: 404);
    return AppException(_genericMessage, statusCode: status);
  }

  @override
  String toString() => 'AppException($code, $statusCode): $message';
}
