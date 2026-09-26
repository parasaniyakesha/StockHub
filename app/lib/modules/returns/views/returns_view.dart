import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/data_table_view.dart';
import '../../../core/widgets/filter_bar.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/sales.dart';
import '../controllers/returns_controller.dart';

class ReturnsView extends StatelessWidget {
  const ReturnsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(ReturnsController(Get.find(), Get.find()));
    return ShellPage(
      title: 'Returns',
      breadcrumb: 'Sales',
      headerActions: [
        if (c.canCreate) FilledButton.icon(onPressed: () => Get.toNamed(AppRoutes.returnNew), icon: const Icon(Icons.add, size: 18), label: const Text('New return')),
      ],
      child: SectionCard(
        padding: EdgeInsets.zero,
        expandChild: true,
        child: Column(children: [
          Obx(() => FilterBar(
                search: SearchField(onChanged: c.setSearch, hint: 'Search return # or invoice…'),
                filters: [
                  if (!c.isStore && c.stores.isNotEmpty)
                    FilterDropdown<String>(label: 'Store', value: c.filters['storeId'] as String?, items: c.stores.map((s) => s.id).toList(), itemLabel: (id) => c.stores.firstWhere((s) => s.id == id).name, onChanged: (v) => c.setFilter('storeId', v)),
                  FilterDropdown<String>(label: 'Condition', value: c.filters['condition'] as String?, items: const ['GOOD', 'DAMAGED'], onChanged: (v) => c.setFilter('condition', v)),
                  DateRangeFilter(start: c.filters['startDate'] as DateTime?, end: c.filters['endDate'] as DateTime?, onChanged: (s, e) => c.setFilters({'startDate': s, 'endDate': e})),
                  if (c.hasActiveFilters) ClearFiltersButton(onPressed: c.clearFilters),
                ],
              )),
          const Divider(height: 1),
          Expanded(
            child: AppDataTable<SaleReturn>(
              controller: c,
              emptyTitle: 'No returns found',
              onRowTap: (r) => Get.toNamed(AppRoutes.saleReturn(r.id)),
              columns: [
                ColumnSpec(label: 'Return #', sortKey: 'returnNumber', width: 120, cell: (r) => Text(r.returnNumber, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                ColumnSpec(label: 'Store', flex: 2, cell: (r) => Text(r.store.name, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                ColumnSpec(label: 'Invoice', width: 110, cell: (r) => Text(r.sale?.name ?? '—', style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Good', width: 70, numeric: true, cell: (r) => Text('${r.goodQuantity}', style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Damaged', width: 80, numeric: true, cell: (r) => r.damagedQuantity > 0 ? Tag('${r.damagedQuantity}', tone: Tone.danger) : const Text('0', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted))),
                ColumnSpec(label: 'Refund', sortKey: 'refundAmount', width: 100, numeric: true, cell: (r) => Text(Fmt.money(r.refundAmount), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                ColumnSpec(label: 'Date', sortKey: 'createdAt', width: 140, cell: (r) => Text(Fmt.dateTime(r.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
