import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../base/view_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, this.icon = Icons.inbox_outlined, this.title = 'Nothing here yet', this.message, this.action, this.compact = false});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? Gap.lg : Gap.xxl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: compact ? 40 : 52,
            height: compact ? 40 : 52,
            decoration: const BoxDecoration(color: AppColors.neutralSoft, shape: BoxShape.circle),
            child: Icon(icon, size: compact ? 20 : 26, color: AppColors.textMuted),
          ),
          const SizedBox(height: Gap.md),
          Text(title, style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: Gap.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(message!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
          if (action != null) ...[const SizedBox(height: Gap.lg), action!],
        ]),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry, this.compact = false});
  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? Gap.lg : Gap.xxl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(color: AppColors.dangerSoft, shape: BoxShape.circle),
            child: const Icon(Icons.cloud_off_outlined, color: AppColors.danger, size: 24),
          ),
          const SizedBox(height: Gap.md),
          Text('Unable to load data', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: Gap.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: Gap.lg),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 18), label: const Text('Try again')),
          ],
        ]),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
        if (message != null) ...[const SizedBox(height: Gap.md), Text(message!, style: Theme.of(context).textTheme.bodySmall)],
      ]),
    );
  }
}

/// Pulsing grey placeholder block for skeleton loading.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 12, this.radius = 4});
  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: const Color(0xFFE7EBF0), borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}

/// Renders the right widget for a [ViewState]. Used by detail screens.
class StateSwitcher extends StatelessWidget {
  const StateSwitcher({
    super.key,
    required this.state,
    required this.builder,
    this.error = '',
    this.onRetry,
    this.empty,
    this.loading,
  });

  final Rx<ViewState> state;
  final Widget Function() builder;
  final String error;
  final VoidCallback? onRetry;
  final Widget? empty;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return Obx(() => switch (state.value) {
          ViewState.loading => loading ?? const LoadingView(),
          ViewState.error => ErrorView(message: error, onRetry: onRetry),
          ViewState.empty => empty ?? const EmptyView(),
          ViewState.success => builder(),
        });
  }
}
