import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/session/settings_service.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/repositories/repositories.dart';

class SettingsPageController extends GetxController {
  SettingsPageController(this._authRepo);
  final AuthRepository _authRepo;

  // Profile
  final profileFormKey = GlobalKey<FormState>();
  late final nameController = TextEditingController(text: Get.find<AuthService>().current?.name);
  late final phoneController = TextEditingController(text: Get.find<AuthService>().current?.phone);
  final savingProfile = false.obs;

  // Password
  final passwordFormKey = GlobalKey<FormState>();
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final changingPassword = false.obs;

  // Company settings (admin)
  final companySaving = false.obs;
  bool get isAdmin => Get.find<AuthService>().isAdmin;

  @override
  void onClose() {
    nameController.dispose();
    phoneController.dispose();
    currentPasswordController.dispose();
    newPasswordController.dispose();
    super.onClose();
  }

  Future<void> saveProfile() async {
    if (!profileFormKey.currentState!.validate()) return;
    savingProfile.value = true;
    try {
      await _authRepo.updateProfile(name: nameController.text.trim(), phone: phoneController.text.trim());
      await Get.find<AuthService>().refreshUser();
      Toast.success('Profile updated');
    } catch (e) {
      Toast.fromError(e);
    } finally {
      savingProfile.value = false;
    }
  }

  Future<void> changePassword() async {
    if (!passwordFormKey.currentState!.validate()) return;
    changingPassword.value = true;
    try {
      await _authRepo.changePassword(currentPasswordController.text, newPasswordController.text);
      Toast.success('Password changed. Please sign in again.');
      currentPasswordController.clear();
      newPasswordController.clear();
      await Get.find<AuthService>().logout(callServer: false);
    } catch (e) {
      Toast.error(AppException.from(e).detailedMessage);
    } finally {
      changingPassword.value = false;
    }
  }

  Future<void> saveCompanySettings(Map<String, dynamic> patch) async {
    companySaving.value = true;
    try {
      final updated = await Get.find<PlatformRepository>().updateSettings(patch);
      Get.find<SettingsService>().apply(updated);
      Toast.success('Settings updated');
    } catch (e) {
      Toast.fromError(e);
    } finally {
      companySaving.value = false;
    }
  }
}
