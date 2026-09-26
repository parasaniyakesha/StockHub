import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'state_views.dart';
import 'status_badge.dart';

/// Bordered white card with optional title row and actions.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.subtitle, this.actions = const [], required this.child, this.padding = const EdgeInsets.all(Gap.lg), this.expandChild = false});

  final String? title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// When true the child fills the remaining height (use inside Expanded).
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    final header = title == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.md, Gap.md),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title!, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: Theme.of(context).textTheme.bodySmall)),
                ]),
              ),
              ...actions,
            ]),
          );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: expandChild ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) ...[header, const Divider()],
          if (expandChild) Expanded(child: Padding(padding: padding, child: child)) else Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// KPI tile for dashboards.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, this.tone = Tone.primary, this.caption, this.onTap, this.loading = false});

  final String label;
  final String value;
  final IconData icon;
  final Tone tone;
  final String? caption;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Gap.sm),
                loading
                    ? const Padding(padding: EdgeInsets.symmetric(vertical: 5), child: Skeleton(width: 90, height: 18))
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.textPrimary)),
                      ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(caption!, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(Radii.md)),
              child: Icon(icon, color: tone.fg, size: 19),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Label/value pairs laid out in a responsive grid (detail screens).
class InfoGrid extends StatelessWidget {
  const InfoGrid({super.key, required this.items, this.columns = 3});
  final List<(String, Widget)> items;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth < 520 ? 1 : c.maxWidth < 820 ? 2 : columns;
      final width = (c.maxWidth - (cols - 1) * Gap.xl) / cols;
      return Wrap(
        spacing: Gap.xl,
        runSpacing: Gap.lg,
        children: [
          for (final (label, value) in items)
            SizedBox(
              width: width,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                DefaultTextStyle.merge(style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary), child: value),
              ]),
            ),
        ],
      );
    });
  }
}

/// Convenience for InfoGrid values.
Widget infoText(String? value) => Text(value == null || value.isEmpty ? '—' : value);

/// Inline notice banner.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.message, this.tone = Tone.info, this.icon, this.action});
  final String message;
  final Tone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 10),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(Radii.md), border: Border.all(color: tone.fg.withValues(alpha: 0.18))),
      child: Row(children: [
        Icon(icon ?? Icons.info_outline, size: 18, color: tone.fg),
        const SizedBox(width: Gap.sm),
        Expanded(child: Text(message, style: TextStyle(fontSize: 12.5, color: tone.fg, height: 1.35))),
        if (action != null) action!,
      ]),
    );
  }
}

/// Circle avatar with initials.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.initials, {super.key, this.size = 32, this.color = AppColors.primary});
  final String initials;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Text(initials, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size * 0.38)),
    );
  }
}
