import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../controllers/sale_detail_controller.dart';

class SaleDetailView extends StatelessWidget {
  const SaleDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final id = Get.parameters['id']!;
    final reused = Get.isRegistered<SaleDetailController>(tag: id);
    final c = Get.put(SaleDetailController(Get.find(), id), tag: id);
    if (reused) c.load();
    return ShellPage(
      title: 'Sale details',
      breadcrumb: 'Sales',
      headerActions: [
        Obx(() {
          final s = c.sale.value;
          if (s == null || s.isCancelled) return const SizedBox();
          return Row(mainAxisSize: MainAxisSize.min, children: [
            if (c.canReturn)
              OutlinedButton(onPressed: () => Get.toNamed(AppRoutes.returnNew, arguments: s), child: const Text('Create return')),
            if (c.canCancel && s.returns.isEmpty) ...[
              const SizedBox(width: Gap.sm),
              OutlinedButton(onPressed: c.acting.value ? null : c.cancel, style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)), child: const Text('Cancel sale')),
            ],
          ]);
        }),
      ],
      child: StateSwitcher(
        state: c.state,
        onRetry: c.load,
        error: c.errorMessage.value,
        builder: () {
          final s = c.sale.value!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(s.invoiceNumber, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(width: Gap.sm),
                  StatusBadge(s.status),
                ]),
                const SizedBox(height: 4),
                Text('${s.store.name} · ${Fmt.dateTime(s.createdAt)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: Gap.xl),
                SectionCard(
                  title: 'Customer & payment',
                  child: InfoGrid(items: [
                    ('Customer', infoText(s.customerName ?? 'Walk-in')),
                    ('Phone', infoText(s.customerPhone)),
                    ('Payment method', infoText(Fmt.enumLabel(s.paymentMethod))),
                    ('Recorded by', infoText(s.createdBy?.name)),
                    if (s.isCancelled) ('Cancelled', infoText('${Fmt.dateTime(s.cancelledAt)} - ${s.cancelReason}')),
                  ]),
                ),
                const SizedBox(height: Gap.lg),
                SectionCard(
                  title: 'Items',
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    Container(
                      color: AppColors.surfaceMuted,
                      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 8),
                      child: const Row(children: [
                        Expanded(flex: 3, child: Text('Product', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        SizedBox(width: 60, child: Text('Qty', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        SizedBox(width: 80, child: Text('Price', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        SizedBox(width: 80, child: Text('Tax', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        SizedBox(width: 90, child: Text('Total', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      ]),
                    ),
                    for (final item in s.items) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 8),
                        child: Row(children: [
                          Expanded(flex: 3, child: Text(item.product.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                          SizedBox(width: 60, child: Text('${item.quantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
                          SizedBox(width: 80, child: Text(Fmt.money(item.unitPrice), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
                          SizedBox(width: 80, child: Text(Fmt.money(item.tax), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
                          SizedBox(width: 90, child: Text(Fmt.money(item.total), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                        ]),
                      ),
                    ],
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        _totalRow('Subtotal', Fmt.money(s.subtotal)),
                        _totalRow('Tax', Fmt.money(s.tax)),
                        _totalRow('Discount', '- ${Fmt.money(s.discount)}'),
                        _totalRow('Grand total', Fmt.money(s.grandTotal), bold: true),
                      ]),
                    ),
                  ]),
                ),
                if (s.returns.isNotEmpty) ...[
                  const SizedBox(height: Gap.lg),
                  SectionCard(
                    title: 'Returns',
                    child: Column(children: [
                      for (final r in s.returns)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(r.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          trailing: Text(Fmt.money(double.tryParse(r.code ?? '0')), style: const TextStyle(fontSize: 13)),
                          onTap: () => Get.toNamed(AppRoutes.saleReturn(r.id)),
                        ),
                    ]),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 100, child: Text(label, textAlign: TextAlign.right, style: TextStyle(fontSize: bold ? 13.5 : 12.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: AppColors.textSecondary))),
          SizedBox(width: 100, child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontSize: bold ? 14.5 : 12.5, fontWeight: FontWeight.w700, color: bold ? AppColors.primary : AppColors.textPrimary))),
        ]),
      );
}
