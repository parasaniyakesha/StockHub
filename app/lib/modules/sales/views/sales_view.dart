import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/data_table_view.dart';
import '../../../core/widgets/filter_bar.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/sales.dart';
import '../controllers/sales_controller.dart';

class SalesView extends StatelessWidget {
  const SalesView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(SalesController(Get.find(), Get.find()));
    return ShellPage(
      title: 'Sales',
      breadcrumb: 'Sales',
      headerActions: [
        if (c.canCreate) FilledButton.icon(onPressed: () => Get.toNamed(AppRoutes.saleNew), icon: const Icon(Icons.add, size: 18), label: const Text('New sale')),
      ],
      child: Column(children: [
        Obx(() {
          final s = c.summary;
          if (s == null) return const SizedBox();
          return Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.xl, 0),
            child: Row(children: [
              _SummaryChip(label: 'Invoices', value: '${s.completedCount}'),
              const SizedBox(width: Gap.md),
              _SummaryChip(label: 'Total', value: Fmt.money(s.completedTotal)),
            ]),
          );
        }),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(Gap.xl),
            child: SectionCard(
              padding: EdgeInsets.zero,
              expandChild: true,
              child: Column(children: [
                Obx(() => FilterBar(
                      search: SearchField(onChanged: c.setSearch, hint: 'Search invoice # or customer…'),
                      filters: [
                        if (!c.isStore && c.stores.isNotEmpty)
                          FilterDropdown<String>(label: 'Store', value: c.filters['storeId'] as String?, items: c.stores.map((s) => s.id).toList(), itemLabel: (id) => c.stores.firstWhere((s) => s.id == id).name, onChanged: (v) => c.setFilter('storeId', v)),
                        FilterDropdown<String>(label: 'Payment', value: c.filters['paymentMethod'] as String?, items: PaymentMethods.all, onChanged: (v) => c.setFilter('paymentMethod', v)),
                        FilterDropdown<String>(label: 'Status', value: c.filters['status'] as String?, items: const ['COMPLETED', 'CANCELLED'], onChanged: (v) => c.setFilter('status', v)),
                        DateRangeFilter(start: c.filters['startDate'] as DateTime?, end: c.filters['endDate'] as DateTime?, onChanged: (s, e) => c.setFilters({'startDate': s, 'endDate': e})),
                        if (c.hasActiveFilters) ClearFiltersButton(onPressed: c.clearFilters),
                      ],
                    )),
                const Divider(height: 1),
                Expanded(
                  child: AppDataTable<Sale>(
                    controller: c,
                    emptyTitle: 'No sales found',
                    onRowTap: (s) => Get.toNamed(AppRoutes.sale(s.id)),
                    columns: [
                      ColumnSpec(label: 'Invoice #', sortKey: 'invoiceNumber', width: 130, cell: (s) => Text(s.invoiceNumber, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                      ColumnSpec(label: 'Store', flex: 2, cell: (s) => Text(s.store.name, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                      ColumnSpec(label: 'Customer', flex: 2, cell: (s) => Text(s.customerName ?? 'Walk-in', style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                      ColumnSpec(label: 'Payment', width: 100, cell: (s) => Tag(s.paymentMethod)),
                      ColumnSpec(label: 'Total', sortKey: 'grandTotal', width: 100, numeric: true, cell: (s) => Text(Fmt.money(s.grandTotal), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                      ColumnSpec(label: 'Status', width: 100, cell: (s) => StatusBadge(s.status)),
                      ColumnSpec(label: 'Date', sortKey: 'createdAt', width: 140, cell: (s) => Text(Fmt.dateTime(s.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
      ]),
    );
  }
}
