import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../controllers/return_detail_controller.dart';

class ReturnDetailView extends StatelessWidget {
  const ReturnDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final id = Get.parameters['id']!;
    final reused = Get.isRegistered<ReturnDetailController>(tag: id);
    final c = Get.put(ReturnDetailController(Get.find(), id), tag: id);
    if (reused) c.load();
    return ShellPage(
      title: 'Return details',
      breadcrumb: 'Sales / Returns',
      child: StateSwitcher(
        state: c.state,
        onRetry: c.load,
        error: c.errorMessage.value,
        builder: () {
          final r = c.saleReturn.value!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.returnNumber, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('${r.store.name} · ${Fmt.dateTime(r.createdAt)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: Gap.xl),
                SectionCard(
                  title: 'Overview',
                  child: InfoGrid(items: [
                    ('Linked invoice', infoText(r.sale?.name)),
                    ('Refund amount', infoText(Fmt.money(r.refundAmount))),
                    ('Recorded by', infoText(r.createdBy?.name)),
                    if (r.notes != null && r.notes!.isNotEmpty) ('Notes', infoText(r.notes)),
                  ]),
                ),
                const SizedBox(height: Gap.lg),
                SectionCard(
                  title: 'Returned items',
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (final item in r.items) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 10),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(item.product.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                              Text(item.reason, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                            ]),
                          ),
                          Tag(item.condition, tone: item.condition == 'DAMAGED' ? Tone.danger : Tone.success),
                          const SizedBox(width: Gap.md),
                          Text('${item.quantity} × ${Fmt.money(item.unitPrice)}', style: const TextStyle(fontSize: 12.5)),
                        ]),
                      ),
                      const Divider(height: 1),
                    ],
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}
