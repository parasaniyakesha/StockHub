import 'package:get/get.dart';

import '../../data/models/user.dart';
import '../../data/repositories/repositories.dart';
import '../network/api_client.dart';
import '../routes/app_routes.dart';
import '../storage/preferences.dart';
import '../storage/token_storage.dart';
import '../widgets/toast.dart';
import 'notification_center.dart';
import 'settings_service.dart';

/// Holds the signed-in user and session lifecycle. UI permissions derive from
/// [user]; they are convenience only - the API enforces authorization.
class AuthService extends GetxService {
  AuthService(this._tokens, this._client, this._repo);

  final TokenStorage _tokens;
  final ApiClient _client;
  final AuthRepository _repo;

  final user = Rxn<AppUser>();

  bool get isLoggedIn => user.value != null;
  AppUser? get current => user.value;
  bool get isAdmin => user.value?.isAdmin ?? false;
  bool get isManager => user.value?.isManager ?? false;
  bool get isStore => user.value?.isStore ?? false;

  bool can(String permission) => user.value?.can(permission) ?? false;
  bool canAny(Iterable<String> permissions) => permissions.any(can);
  bool hasRole(Iterable<String> roles) => user.value != null && roles.contains(user.value!.role);

  bool _expiring = false;

  /// Restores a persisted session at startup. Returns true if signed in.
  Future<bool> restore() async {
    _client.onSessionExpired = _handleExpired;
    _client.onUserRefreshed = (json) => user.value = AppUser.fromJson(json);
    await _tokens.load();
    if (!_tokens.hasSession) return false;
    final ok = await _client.refreshSession();
    if (!ok) {
      await _tokens.clear();
      return false;
    }
    try {
      user.value = await _repo.me();
      await _afterSignIn();
      return true;
    } catch (_) {
      await _tokens.clear();
      user.value = null;
      return false;
    }
  }

  Future<void> login(String email, String password) async {
    final session = await _repo.login(email.trim(), password);
    await _tokens.save(accessToken: session.accessToken, refreshToken: session.refreshToken);
    user.value = session.user;
    Preferences.lastEmail = session.user.email;
    await _afterSignIn();
  }

  Future<void> _afterSignIn() async {
    _expiring = false;
    await Get.find<SettingsService>().load();
    Get.find<NotificationCenter>().start();
  }

  Future<void> refreshUser() async {
    try {
      user.value = await _repo.me();
    } catch (_) {}
  }

  Future<void> logout({bool callServer = true}) async {
    final refresh = _tokens.refreshToken;
    Get.find<NotificationCenter>().stop();
    if (callServer && refresh != null) {
      try {
        await _repo.logout(refresh);
      } catch (_) {
        // Signing out locally must never fail.
      }
    }
    await _tokens.clear();
    user.value = null;
    Get.offAllNamed(AppRoutes.login);
  }

  void _handleExpired() {
    if (_expiring || user.value == null) return;
    _expiring = true;
    logout(callServer: false).then((_) => Toast.info('Your session has expired. Please sign in again.'));
  }
}
