import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores session tokens in the OS secure store (Windows Credential Manager,
/// macOS Keychain, libsecret on Linux). Tokens are kept in memory for requests.
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _accessKey = 'stockhub.accessToken';
  static const _refreshKey = 'stockhub.refreshToken';

  String? _access;
  String? _refresh;

  String? get accessToken => _access;
  String? get refreshToken => _refresh;
  bool get hasSession => _refresh != null;

  Future<void> load() async {
    try {
      _access = await _storage.read(key: _accessKey);
      _refresh = await _storage.read(key: _refreshKey);
    } catch (_) {
      // Corrupt/unavailable keystore: behave as signed out.
      _access = null;
      _refresh = null;
    }
  }

  Future<void> save({required String accessToken, required String refreshToken}) async {
    _access = accessToken;
    _refresh = refreshToken;
    try {
      await _storage.write(key: _accessKey, value: accessToken);
      await _storage.write(key: _refreshKey, value: refreshToken);
    } catch (_) {
      // Session still works for this run even if persistence fails.
    }
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    try {
      await _storage.delete(key: _accessKey);
      await _storage.delete(key: _refreshKey);
    } catch (_) {}
  }
}
