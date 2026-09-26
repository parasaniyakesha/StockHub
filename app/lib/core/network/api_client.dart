import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:get/get.dart' hide Response, FormData;

import '../constants/app_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

typedef Json = Map<String, dynamic>;

class DownloadedFile {
  const DownloadedFile(this.fileName, this.bytes, this.contentType);
  final String fileName;
  final Uint8List bytes;
  final String contentType;
}

/// Single HTTP entry point. Adds the bearer token, transparently refreshes an
/// expired access token once (single-flight) and retries, and converts every
/// failure into an [AppException]. Only repositories/services may use it -
/// never widgets.
class ApiClient extends GetxService {
  ApiClient(this._tokens) {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      contentType: 'application/json',
      responseType: ResponseType.json,
    ));
    _refreshDio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: AppConfig.connectTimeout));
    // Never ships in a release build, regardless of build flags.
    if (kDebugMode) _dio.interceptors.add(_ApiLogInterceptor());
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest, onError: _onError));
  }

  final TokenStorage _tokens;
  late final Dio _dio;
  late final Dio _refreshDio;
  Completer<bool>? _refreshing;

  /// Called when the session can no longer be refreshed (set by AuthService).
  void Function()? onSessionExpired;

  /// Called after a successful token refresh with the fresh user payload.
  void Function(Json user)? onUserRefreshed;

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _tokens.accessToken;
    if (token != null && options.extra['skipAuth'] != true) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final code = response?.data is Map ? (response!.data as Map)['code'] : null;
    final isAuthCall = err.requestOptions.path.startsWith('/auth/login') || err.requestOptions.path.startsWith('/auth/refresh');
    final retried = err.requestOptions.extra['retried'] == true;

    if (response?.statusCode == 401 && !isAuthCall && !retried && _tokens.hasSession && (code == 'TOKEN_EXPIRED' || code == 'UNAUTHORIZED')) {
      final refreshed = await refreshSession();
      if (refreshed) {
        try {
          final opts = err.requestOptions
            ..extra['retried'] = true
            ..headers['Authorization'] = 'Bearer ${_tokens.accessToken}';
          return handler.resolve(await _dio.fetch(opts));
        } on DioException catch (e) {
          return handler.next(e);
        }
      }
      onSessionExpired?.call();
    }
    handler.next(err);
  }

  /// Exchanges the refresh token for a new pair. Concurrent callers share one request.
  Future<bool> refreshSession() async {
    if (_refreshing != null) return _refreshing!.future;
    final completer = _refreshing = Completer<bool>();
    try {
      final refresh = _tokens.refreshToken;
      if (refresh == null) {
        completer.complete(false);
      } else {
        final res = await _refreshDio.post<Json>('/auth/refresh', data: {'refreshToken': refresh});
        final data = res.data!['data'] as Json;
        await _tokens.save(accessToken: data['accessToken'] as String, refreshToken: data['refreshToken'] as String);
        if (data['user'] is Json) onUserRefreshed?.call(data['user'] as Json);
        completer.complete(true);
      }
    } catch (_) {
      completer.complete(false);
    } finally {
      _refreshing = null;
    }
    return completer.future;
  }

  Future<Json> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      final data = res.data;
      if (data is Json) return data;
      return {'success': true, 'data': data};
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<Json> get(String path, {Map<String, dynamic>? query}) => _send(() => _dio.get(path, queryParameters: query));

  Future<Json> post(String path, {Object? body, bool skipAuth = false}) =>
      _send(() => _dio.post(path, data: body ?? const {}, options: Options(extra: {'skipAuth': skipAuth})));

  Future<Json> put(String path, {Object? body}) => _send(() => _dio.put(path, data: body ?? const {}));

  Future<Json> patch(String path, {Object? body}) => _send(() => _dio.patch(path, data: body ?? const {}));

  Future<Json> delete(String path, {Map<String, dynamic>? query}) => _send(() => _dio.delete(path, queryParameters: query));

  /// Downloads a binary export (CSV/XLSX/PDF). The server names the file.
  Future<DownloadedFile> download(String path, {Map<String, dynamic>? query, String fallbackName = 'export'}) async {
    try {
      final res = await _dio.get<List<int>>(path, queryParameters: query, options: Options(responseType: ResponseType.bytes));
      final disposition = res.headers.value('content-disposition') ?? '';
      final match = RegExp(r'filename="?([^";]+)"?').firstMatch(disposition);
      return DownloadedFile(
        match?.group(1) ?? fallbackName,
        Uint8List.fromList(res.data ?? const []),
        res.headers.value('content-type') ?? 'application/octet-stream',
      );
    } on DioException catch (e) {
      // Error bodies arrive as bytes here; surface a friendly message.
      if (e.response?.statusCode == 403) throw AppException('You do not have permission to export this.', code: 'FORBIDDEN', statusCode: 403);
      throw AppException.from(e);
    } catch (e) {
      throw AppException.from(e);
    }
  }
}

/// Debug-only: prints every outgoing request (method, URL, body) and every
/// response/error (status, URL, body) so API traffic is visible in the
/// console while developing. Never active in a release build. Secrets
/// (passwords, tokens) are redacted before printing; binary responses are
/// summarised rather than dumped.
class _ApiLogInterceptor extends Interceptor {
  static const _redactedKeys = {'password', 'newPassword', 'currentPassword', 'refreshToken', 'accessToken', 'token'};

  static Object? _redact(Object? data) {
    if (data is Map) return data.map((k, v) => MapEntry(k, _redactedKeys.contains(k) ? '••••••' : _redact(v)));
    if (data is List) return data.map(_redact).toList();
    return data;
  }

  static String _describe(Response<dynamic> response) {
    if (response.requestOptions.responseType == ResponseType.bytes) {
      final bytes = response.data is List ? (response.data as List).length : 0;
      return '<binary, $bytes bytes>';
    }
    return '${_redact(response.data)}';
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('➡️ [API] ${options.method} ${options.uri}${options.data != null ? '\n    body: ${_redact(options.data)}' : ''}');
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    debugPrint('⬅️ [API] ${response.statusCode} ${response.requestOptions.method} ${response.requestOptions.uri}\n    response: ${_describe(response)}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final res = err.response;
    debugPrint(
      '✖️ [API] ${res?.statusCode ?? '-'} ${err.requestOptions.method} ${err.requestOptions.uri}\n'
      '    error: ${res != null ? _describe(res) : err.message}',
    );
    handler.next(err);
  }
}
