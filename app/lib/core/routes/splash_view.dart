import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../constants/app_config.dart';
import '../session/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/brand_logo.dart';
import 'app_routes.dart';

/// Shown while the persisted session is restored at startup.
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final signedIn = await Get.find<AuthService>().restore();
      Get.offAllNamed(signedIn ? AppRoutes.dashboard : AppRoutes.login);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          BrandLogo(size: 64),
          SizedBox(height: 16),
          Text(AppConfig.appName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 24),
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        ]),
      ),
    );
  }
}
