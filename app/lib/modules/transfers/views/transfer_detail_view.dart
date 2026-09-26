import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../controllers/transfer_detail_controller.dart';

class TransferDetailView extends StatelessWidget {
  const TransferDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final id = Get.parameters['id']!;
    final reused = Get.isRegistered<TransferDetailController>(tag: id);
    final c = Get.put(TransferDetailController(Get.find(), id), tag: id);
    if (reused) c.load();
    return ShellPage(
      title: 'Stock transfer',
      breadcrumb: 'Operations / Transfers',
      headerActions: [
        Obx(() {
          final t = c.transfer.value;
          if (t == null) return const SizedBox();
          final busy = c.acting.value;
          final buttons = <Widget>[];
          if (t.can('reject')) buttons.add(OutlinedButton(onPressed: busy ? null : c.reject, style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)), child: const Text('Reject')));
          if (t.can('approve')) buttons.add(FilledButton(onPressed: busy ? null : c.approve, child: const Text('Approve')));
          if (t.can('dispatch')) buttons.add(FilledButton(onPressed: busy ? null : c.dispatch, child: const Text('Dispatch')));
          if (t.can('receive')) buttons.add(FilledButton(onPressed: busy ? null : c.receive, child: const Text('Receive')));
          if (t.can('complete')) buttons.add(FilledButton(onPressed: busy ? null : c.complete, child: const Text('Close')));
          if (t.can('cancel')) buttons.add(TextButton(onPressed: busy ? null : c.cancel, child: const Text('Cancel', style: TextStyle(color: AppColors.danger))));
          return Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < buttons.length; i++) ...[if (i > 0) const SizedBox(width: Gap.sm), buttons[i]]]);
        }),
      ],
      child: StateSwitcher(
        state: c.state,
        onRetry: c.load,
        error: c.errorMessage.value,
        builder: () {
          final t = c.transfer.value!;
          final editable = t.status == 'REQUESTED' && t.can('approve');
          return SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(t.transferNumber, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(width: Gap.sm),
                StatusBadge(t.status),
              ]),
              const SizedBox(height: 4),
              Text('${t.source.name} → ${t.toStore.name} · Created ${Fmt.dateTime(t.createdAt)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: Gap.xl),
              if (t.rejectionReason != null) Padding(padding: const EdgeInsets.only(bottom: Gap.lg), child: InfoBanner(message: t.rejectionReason!, tone: Tone.danger, icon: Icons.block)),
              SectionCard(
                title: 'Products',
                padding: EdgeInsets.zero,
                child: Column(children: [
                  Container(
                    color: AppColors.surfaceMuted,
                    padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 8),
                    child: Row(children: [
                      const Expanded(flex: 3, child: Text('Product', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      const SizedBox(width: 80, child: Text('Requested', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      SizedBox(width: editable ? 100 : 80, child: Text(editable ? 'Approve' : 'Approved', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      if (!editable) ...[
                        const SizedBox(width: 80, child: Text('Dispatched', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        const SizedBox(width: 80, child: Text('Received', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      ],
                    ]),
                  ),
                  for (final item in t.items) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 8),
                      child: Row(children: [
                        Expanded(flex: 3, child: Text(item.product.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                        SizedBox(width: 80, child: Text('${item.requestedQuantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
                        SizedBox(
                          width: editable ? 100 : 80,
                          child: editable
                              ? Align(alignment: Alignment.centerRight, child: Obx(() => QuantityInput(value: c.approvals[item.id] ?? 0, max: item.requestedQuantity, onChanged: (v) => c.approvals[item.id] = v)))
                              : Text(item.approvedQuantity?.toString() ?? '—', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ),
                        if (!editable) ...[
                          SizedBox(width: 80, child: Text('${item.dispatchedQuantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
                          SizedBox(width: 80, child: Text('${item.receivedQuantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                        ],
                      ]),
                    ),
                  ],
                ]),
              ),
              if (t.notes != null && t.notes!.isNotEmpty) ...[
                const SizedBox(height: Gap.lg),
                SectionCard(title: 'Notes', child: Text(t.notes!, style: const TextStyle(fontSize: 13, height: 1.4))),
              ],
            ]),
          );
        },
      ),
    );
  }
}
