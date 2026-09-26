import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'core/constants/app_config.dart';
import 'core/network/api_client.dart';
import 'core/routes/app_pages.dart';
import 'core/routes/app_routes.dart';
import 'core/session/auth_service.dart';
import 'core/session/notification_center.dart';
import 'core/session/settings_service.dart';
import 'core/storage/preferences.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/repositories.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Preferences.init();

  final tokens = TokenStorage();
  final client = ApiClient(tokens);
  registerRepositories(client);
  Get.put(AuthService(tokens, client, Get.find()), permanent: true);
  Get.put(SettingsService(Get.find()), permanent: true);
  Get.put(NotificationCenter(Get.find()), permanent: true);

  runApp(const StockHubApp());
}

class StockHubApp extends StatelessWidget {
  const StockHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: AppRoutes.splash,
      getPages: AppPages.routes,
      defaultTransition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 150),
    );
  }
}
