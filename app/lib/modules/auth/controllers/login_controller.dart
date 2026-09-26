import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/storage/preferences.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/repositories/repositories.dart';

class LoginController extends GetxController {
  final formKey = GlobalKey<FormState>();
  late final emailController = TextEditingController(text: Preferences.lastEmail ?? '');
  final passwordController = TextEditingController();

  final loading = false.obs;
  final obscure = true.obs;
  final errorMessage = RxnString();
  final fieldErrors = <String, String>{}.obs;

  void toggleObscure() => obscure.value = !obscure.value;

  @override
  void onClose() {
    emailController.dispose();
    passwordController.dispose();
    super.onClose();
  }

  Future<void> submit() async {
    errorMessage.value = null;
    fieldErrors.clear();
    if (!formKey.currentState!.validate()) return;
    loading.value = true;
    try {
      await Get.find<AuthService>().login(emailController.text, passwordController.text);
      Get.offAllNamed(AppRoutes.dashboard);
    } catch (e) {
      final err = AppException.from(e);
      fieldErrors.assignAll(err.fieldErrors);
      if (err.fieldErrors.isEmpty) errorMessage.value = err.message;
    } finally {
      loading.value = false;
    }
  }
}

class ForgotPasswordController extends GetxController {
  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final loading = false.obs;
  final sent = false.obs;
  final devResetToken = RxnString();

  // Step 2: redeem the code for a new password.
  final resetFormKey = GlobalKey<FormState>();
  final tokenController = TextEditingController();
  final newPasswordController = TextEditingController();
  final enteringCode = false.obs;
  final resetting = false.obs;
  final resetDone = false.obs;

  @override
  void onClose() {
    emailController.dispose();
    tokenController.dispose();
    newPasswordController.dispose();
    super.onClose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    loading.value = true;
    try {
      devResetToken.value = await Get.find<AuthRepository>().forgotPassword(emailController.text.trim());
      if (devResetToken.value != null) tokenController.text = devResetToken.value!;
      sent.value = true;
    } catch (e) {
      Toast.fromError(e);
    } finally {
      loading.value = false;
    }
  }

  void showEnterCode() => enteringCode.value = true;

  Future<void> submitReset() async {
    if (!resetFormKey.currentState!.validate()) return;
    resetting.value = true;
    try {
      await Get.find<AuthRepository>().resetPassword(tokenController.text.trim(), newPasswordController.text);
      resetDone.value = true;
    } catch (e) {
      Toast.fromError(e);
    } finally {
      resetting.value = false;
    }
  }
}
