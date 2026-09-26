import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Standard dialog frame: title bar with close button, scrollable body, action row.
class AppDialog extends StatelessWidget {
  const AppDialog({super.key, required this.title, required this.child, this.actions = const [], this.width = 520, this.subtitle, this.scrollable = true});

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.md, Gap.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: Theme.of(context).textTheme.titleLarge),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'Close', icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.of(context).maybePop()),
                ],
              ),
            ),
            const Divider(),
            Flexible(
              child: scrollable
                  ? SingleChildScrollView(padding: const EdgeInsets.all(Gap.xl), child: child)
                  : Padding(padding: const EdgeInsets.all(Gap.xl), child: child),
            ),
            if (actions.isNotEmpty) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.xl, vertical: Gap.md),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: Gap.sm), actions[i]],
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Returns true when confirmed.
Future<bool> confirmDialog({
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await Get.dialog<bool>(
    AppDialog(
      title: title,
      width: 440,
      actions: [
        OutlinedButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Get.back(result: true),
          child: Text(confirmLabel),
        ),
      ],
      child: Text(message, style: const TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.textSecondary)),
    ),
  );
  return result ?? false;
}

/// Asks for a (required by default) reason. Returns null when cancelled.
Future<String?> reasonDialog({
  required String title,
  String label = 'Reason',
  String? message,
  String confirmLabel = 'Submit',
  bool required = true,
  bool destructive = false,
}) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final result = await Get.dialog<String>(
    AppDialog(
      title: title,
      width: 460,
      actions: [
        OutlinedButton(onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () {
            if (formKey.currentState!.validate()) Get.back(result: controller.text.trim());
          },
          child: Text(confirmLabel),
        ),
      ],
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message != null) ...[
              Text(message, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
              const SizedBox(height: Gap.lg),
            ],
            TextFormField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(labelText: required ? '$label *' : label),
              validator: (v) => required && (v == null || v.trim().isEmpty) ? '$label is required' : null,
            ),
          ],
        ),
      ),
    ),
  );
  controller.dispose();
  return result;
}

/// Right-docked side panel for details and long forms.
Future<T?> showSidePanel<T>({required Widget child, double width = 560}) {
  return Get.generalDialog<T>(
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x520F172A),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: AppColors.surface,
        elevation: 12,
        child: SizedBox(width: width, height: double.infinity, child: child),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// Header for [showSidePanel] contents.
class SidePanelHeader extends StatelessWidget {
  const SidePanelHeader({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.md, Gap.lg),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: Theme.of(context).textTheme.bodySmall)),
          ]),
        ),
        if (trailing != null) trailing!,
        IconButton(tooltip: 'Close', icon: const Icon(Icons.close, size: 20), onPressed: () => Get.back()),
      ]),
    );
  }
}
