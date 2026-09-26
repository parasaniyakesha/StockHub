import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../session/auth_service.dart';
import 'app_routes.dart';
import 'nav_items.dart';

/// Redirects to the login screen when there is no session.
class AuthGuard extends GetMiddleware {
  @override
  int? get priority => 1;

  @override
  RouteSettings? redirect(String? route) {
    final auth = Get.find<AuthService>();
    return auth.isLoggedIn ? null : const RouteSettings(name: AppRoutes.login);
  }
}

/// Blocks routes the current role / permissions cannot use (UI convenience -
/// the API rejects the same requests with 403).
class AccessGuard extends GetMiddleware {
  AccessGuard(this.access);
  final Access access;

  @override
  int? get priority => 2;

  @override
  RouteSettings? redirect(String? route) {
    final auth = Get.find<AuthService>();
    if (!auth.isLoggedIn) return const RouteSettings(name: AppRoutes.login);
    return access.allows(auth) ? null : const RouteSettings(name: AppRoutes.dashboard);
  }
}

/// Signed-in users are sent from the login screen to the dashboard.
class GuestGuard extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    final auth = Get.find<AuthService>();
    return auth.isLoggedIn ? const RouteSettings(name: AppRoutes.dashboard) : null;
  }
}
