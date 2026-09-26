import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/form_fields.dart';
import '../controllers/login_controller.dart';

class ForgotPasswordView extends StatelessWidget {
  const ForgotPasswordView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(ForgotPasswordController());
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Gap.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Gap.xxl),
                child: Obx(() {
                if (c.resetDone.value) return _DoneState();
                if (c.sent.value && c.enteringCode.value) return _ResetState(c: c);
                if (c.sent.value) return _SentState(c: c);
                return _RequestState(c: c);
              }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestState extends StatelessWidget {
  const _RequestState({required this.c});
  final ForgotPasswordController c;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: c.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(alignment: Alignment.centerLeft, icon: const Icon(Icons.arrow_back), onPressed: Get.back, padding: EdgeInsets.zero),
          const SizedBox(height: Gap.sm),
          Text('Reset your password', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: Gap.xs),
          const Text('Enter your account email and we will send you a reset code.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: Gap.xl),
          AppTextField(label: 'Email address', controller: c.emailController, required: true, prefixIcon: Icons.mail_outline, validator: V.all([V.required('Email'), V.email])),
          const SizedBox(height: Gap.xl),
          Obx(() => FilledButton(
                onPressed: c.loading.value ? null : c.submit,
                child: c.loading.value ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Send reset code'),
              )),
        ],
      ),
    );
  }
}

class _SentState extends StatelessWidget {
  const _SentState({required this.c});
  final ForgotPasswordController c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 40, color: AppColors.success),
        const SizedBox(height: Gap.lg),
        Text('Check your email', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: Gap.sm),
        const Text(
          'If an account exists for this email, a reset code has been sent. It is valid for a limited time.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        ),
        if (c.devResetToken.value != null) ...[
          const SizedBox(height: Gap.lg),
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(Radii.md)),
            child: Column(children: [
              const Text('Development mode (no email server configured):', style: TextStyle(fontSize: 11.5, color: AppColors.warning)),
              const SizedBox(height: 4),
              SelectableText(c.devResetToken.value!, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.warning)),
            ]),
          ),
        ],
        const SizedBox(height: Gap.xl),
        FilledButton(onPressed: c.showEnterCode, child: const Text('I have a reset code')),
        const SizedBox(height: Gap.sm),
        OutlinedButton(onPressed: Get.back, child: const Text('Back to sign in')),
      ],
    );
  }
}

class _ResetState extends StatelessWidget {
  const _ResetState({required this.c});
  final ForgotPasswordController c;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: c.resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(alignment: Alignment.centerLeft, icon: const Icon(Icons.arrow_back), onPressed: () => c.enteringCode.value = false, padding: EdgeInsets.zero),
          const SizedBox(height: Gap.sm),
          Text('Enter your reset code', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: Gap.xs),
          const Text('Paste the code we sent you and choose a new password.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: Gap.xl),
          AppTextField(label: 'Reset code', controller: c.tokenController, required: true, prefixIcon: Icons.vpn_key_outlined, validator: V.required('Reset code')),
          const SizedBox(height: Gap.lg),
          AppTextField(label: 'New password', controller: c.newPasswordController, required: true, prefixIcon: Icons.lock_outline, obscure: true, validator: V.password),
          const SizedBox(height: Gap.xl),
          Obx(() => FilledButton(
                onPressed: c.resetting.value ? null : c.submitReset,
                child: c.resetting.value ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Reset password'),
              )),
        ],
      ),
    );
  }
}

class _DoneState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_outline, size: 40, color: AppColors.success),
        const SizedBox(height: Gap.lg),
        Text('Password reset', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: Gap.sm),
        const Text('Your password has been changed. Please sign in with your new password.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
        const SizedBox(height: Gap.xl),
        FilledButton(onPressed: Get.back, child: const Text('Back to sign in')),
      ],
    );
  }
}
