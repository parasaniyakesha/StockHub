import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../core/widgets/form_fields.dart';
import '../controllers/login_controller.dart';

class LoginView extends StatelessWidget {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(LoginController());
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Base: a richer, multi-stop blue rather than a flat two-tone fill,
          // so a maximised window still reads as designed, not empty.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primary, Color(
                    0xFF8AB4FF), Color(0xFF8AB4FF)],
                // stops: [0.0, 0.42, 0.75, 1.0],
              ),
            ),
          ),
          // Faint technical texture - a common enterprise-SaaS cue.
          const Positioned.fill(child: CustomPaint(painter: _DotGridPainter())),
          // Soft glows for depth, kept subtle so they never compete with the card.
          const Positioned(top: -160, left: -140, child: _Glow(color: Color(0xFF7DD3FC), opacity: 0.20, size: 480)),
          const Positioned(bottom: -200, right: -160, child: _Glow(color: AppColors.purple, opacity: 0.22, size: 560)),
          const Positioned(top: -80, right: 120, child: _Glow(color: Color(0xFF34D399), opacity: 0.14, size: 320)),
          // Gentle vignette so the eye settles on the centered card.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: Alignment.center, radius: 1.1, colors: [Colors.transparent, Color(0x14051B4D)]),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Gap.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandLogo(size: 56),
                    const SizedBox(height: Gap.lg),
                    const Text(AppConfig.appName, style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    const Text(
                      'Central catalog, warehouse & store stock, packing orders and sales.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 13.5),
                    ),
                    const SizedBox(height: Gap.xxl),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        padding: const EdgeInsets.all(Gap.xxl),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(color: Color(0x40030B2E), blurRadius: 56, offset: Offset(0, 28)),
                            BoxShadow(color: Color(0x22030B2E), blurRadius: 8, offset: Offset(0, 2)),
                          ],
                        ),
                        child: _LoginForm(c: c),
                      ),
                    ),
                    const SizedBox(height: Gap.xxl),
                    Text('© ${DateTime.now().year} ${AppConfig.appName}. All rights reserved.', style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint repeating dot grid - a subtle enterprise-dashboard texture cue.
/// Cheap to paint (one loop, no blur) so it's fine to redraw on resize.
class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  static const _spacing = 28.0;
  static const _radius = 1.1;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.06);
    for (double y = 0; y < size.height; y += _spacing) {
      for (double x = 0; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), _radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Soft, out-of-focus color wash for background depth. Purely decorative.
class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.opacity, required this.size});
  final Color color;
  final double opacity;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: opacity)),
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({required this.c});
  final LoginController c;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: c.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Sign in', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: Gap.xs),
          const Text('Enter your credentials to access your workspace.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: Gap.xl),
          Obx(() => c.errorMessage.value == null
              ? const SizedBox()
              : Padding(
                  padding: const EdgeInsets.only(bottom: Gap.lg),
                  child: Container(
                    padding: const EdgeInsets.all(Gap.md),
                    decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(Radii.md)),
                    child: Row(children: [
                      const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
                      const SizedBox(width: Gap.sm),
                      Expanded(child: Text(c.errorMessage.value!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5))),
                    ]),
                  ),
                )),
          Obx(() => AppTextField(
                label: 'Email address',
                controller: c.emailController,
                required: true,
                prefixIcon: Icons.mail_outline,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                serverError: c.fieldErrors['email'],
                validator: V.all([V.required('Email'), V.email]),
                onSubmitted: (_) {},
              )),
          const SizedBox(height: Gap.lg),
          Obx(() => AppTextField(
                label: 'Password',
                controller: c.passwordController,
                required: true,
                prefixIcon: Icons.lock_outline,
                obscure: c.obscure.value,
                textInputAction: TextInputAction.done,
                serverError: c.fieldErrors['password'],
                validator: V.required('Password'),
                onSubmitted: (_) => c.submit(),
                suffix: IconButton(
                  icon: Icon(c.obscure.value ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                  onPressed: c.toggleObscure,
                ),
              )),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => Get.toNamed(AppRoutes.forgotPassword), child: const Text('Forgot password?')),
          ),
          const SizedBox(height: Gap.sm),
          Obx(() => FilledButton(
                onPressed: c.loading.value ? null : c.submit,
                child: c.loading.value
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Sign in'),
              )),
        ],
      ),
    );
  }
}
