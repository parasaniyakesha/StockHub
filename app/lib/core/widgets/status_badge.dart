import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/formatters.dart';

enum Tone { neutral, info, success, warning, danger, primary, purple }

extension ToneColors on Tone {
  Color get fg => switch (this) {
        Tone.neutral => AppColors.neutral,
        Tone.info => AppColors.info,
        Tone.success => AppColors.success,
        Tone.warning => AppColors.warning,
        Tone.danger => AppColors.danger,
        Tone.primary => AppColors.primary,
        Tone.purple => AppColors.purple,
      };
  Color get bg => switch (this) {
        Tone.neutral => AppColors.neutralSoft,
        Tone.info => AppColors.infoSoft,
        Tone.success => AppColors.successSoft,
        Tone.warning => AppColors.warningSoft,
        Tone.danger => AppColors.dangerSoft,
        Tone.primary => AppColors.primarySoft,
        Tone.purple => AppColors.purpleSoft,
      };
}

/// Maps every workflow status used by the API to a consistent tone.
Tone toneForStatus(String status) => switch (status) {
      'ACTIVE' || 'COMPLETED' || 'APPROVED' || 'RECEIVED_OK' || 'GOOD' || 'IN' => Tone.success,
      'INACTIVE' || 'CANCELLED' || 'DRAFT' => Tone.neutral,
      'REJECTED' || 'DAMAGED' || 'DAMAGE' || 'OUT' => Tone.danger,
      'SUBMITTED' || 'REQUESTED' || 'ASSIGNED' || 'PENDING' => Tone.info,
      'UNDER_REVIEW' || 'PARTIALLY_APPROVED' || 'PACKING' || 'RECEIVED' || 'LOW' => Tone.warning,
      'PACKED' || 'DISPATCHED' => Tone.purple,
      'ADMIN' => Tone.primary,
      'MANAGER' => Tone.purple,
      'STORE' => Tone.info,
      _ => Tone.neutral,
    };

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.label, this.tone, this.dense = false});

  final String status;
  final String? label;
  final Tone? tone;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = tone ?? toneForStatus(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 1 : 3),
      decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: t.fg, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label ?? Fmt.enumLabel(status), style: TextStyle(color: t.fg, fontSize: dense ? 11 : 11.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Small rectangular tag (e.g. SKU, movement type, role).
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.tone = Tone.neutral, this.icon});
  final String text;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(4)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: tone.fg), const SizedBox(width: 3)],
        Text(text, style: TextStyle(color: tone.fg, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
      ]),
    );
  }
}
