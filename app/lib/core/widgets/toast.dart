import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../network/api_exception.dart';
import '../theme/app_colors.dart';

/// Desktop-style toasts (bottom-right, compact).
class Toast {
  Toast._();

  static void success(String message) => _show(message, AppColors.success, Icons.check_circle_outline);
  static void info(String message) => _show(message, AppColors.info, Icons.info_outline);
  static void warning(String message) => _show(message, AppColors.warning, Icons.warning_amber_outlined);
  static void error(String message) => _show(message, AppColors.danger, Icons.error_outline, seconds: 5);

  /// Shows the user-safe message of any error.
  static void fromError(Object error) => Toast.error(AppException.from(error).detailedMessage);

  static void _show(String message, Color color, IconData icon, {int seconds = 3}) {
    if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
    Get.rawSnackbar(
      messageText: Text(message, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.35)),
      icon: Padding(padding: const EdgeInsets.only(left: 4), child: Icon(icon, color: color, size: 20)),
      backgroundColor: AppColors.surface,
      borderColor: AppColors.border,
      borderWidth: 1,
      leftBarIndicatorColor: color,
      borderRadius: 8,
      maxWidth: 420,
      margin: const EdgeInsets.only(right: 24, bottom: 24, left: 24),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      snackPosition: SnackPosition.BOTTOM,
      snackStyle: SnackStyle.FLOATING,
      boxShadows: const [BoxShadow(color: Color(0x1A0F172A), blurRadius: 16, offset: Offset(0, 6))],
      duration: Duration(seconds: seconds),
      animationDuration: const Duration(milliseconds: 200),
    );
  }
}
