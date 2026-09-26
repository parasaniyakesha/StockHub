import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/data_table_view.dart';
import '../../../core/widgets/filter_bar.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/stock.dart';
import '../controllers/stock_movements_controller.dart';

class StockMovementsView extends StatelessWidget {
  const StockMovementsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(StockMovementsController(Get.find(), Get.find(), Get.find()));
    return ShellPage(
      title: 'Stock movements',
      breadcrumb: 'Inventory',
      headerActions: [
        PopupMenuButton<String>(
          tooltip: 'Export',
          onSelected: c.export,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'csv', child: Text('Export as CSV')),
            PopupMenuItem(value: 'xlsx', child: Text('Export as Excel')),
            PopupMenuItem(value: 'pdf', child: Text('Export as PDF')),
          ],
          child: Obx(() => Container(
                height: AppTheme.controlHeight,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.sm), border: Border.all(color: AppColors.borderStrong)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  c.exporting.value ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_outlined, size: 16),
                  const SizedBox(width: 8),
                  const Text('Export', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              )),
        ),
      ],
      child: SectionCard(
        padding: EdgeInsets.zero,
        expandChild: true,
        child: Column(children: [
          Obx(() => FilterBar(
                search: SearchField(onChanged: c.setSearch, hint: 'Search products or notes…'),
                filters: [
                  if (!c.isStore) ...[
                    ChoiceChip(label: const Text('Stores'), selected: (c.filters['locationType'] as String?) != 'WAREHOUSE', onSelected: (_) => c.setFilter('locationType', 'STORE')),
                    ChoiceChip(label: const Text('Warehouse'), selected: c.filters['locationType'] == 'WAREHOUSE', onSelected: (_) => c.setFilter('locationType', 'WAREHOUSE')),
                    FilterDropdown<String>(label: 'Store', value: c.filters['storeId'] as String?, items: c.stores.map((s) => s.id).toList(), itemLabel: (id) => c.stores.firstWhere((s) => s.id == id).name, onChanged: (v) => c.setFilter('storeId', v)),
                  ],
                  FilterDropdown<String>(label: 'Type', value: c.filters['type'] as String?, items: MovementTypes.all, onChanged: (v) => c.setFilter('type', v)),
                  FilterDropdown<String>(label: 'Bucket', value: c.filters['bucket'] as String?, items: const ['AVAILABLE', 'DAMAGED'], onChanged: (v) => c.setFilter('bucket', v)),
                  DateRangeFilter(start: c.filters['startDate'] as DateTime?, end: c.filters['endDate'] as DateTime?, onChanged: (s, e) => c.setFilters({'startDate': s, 'endDate': e})),
                  if (c.hasActiveFilters) ClearFiltersButton(onPressed: c.clearFilters),
                ],
              )),
          const Divider(height: 1),
          Expanded(
            child: AppDataTable<StockMovement>(
              controller: c,
              emptyTitle: 'No stock movements found',
              columns: [
                ColumnSpec(label: 'Date', sortKey: 'createdAt', width: 150, cell: (m) => Text(Fmt.dateTime(m.createdAt), style: const TextStyle(fontSize: 12))),
                ColumnSpec(label: 'Product', flex: 2, cell: (m) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.product.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(m.product.sku, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ])),
                ColumnSpec(label: 'Location', flex: 1, cell: (m) => Text(m.location.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                ColumnSpec(label: 'Type', sortKey: 'type', width: 110, cell: (m) => StatusBadge(m.type, dense: true)),
                ColumnSpec(label: 'Qty', sortKey: 'quantity', width: 80, numeric: true, cell: (m) => Text(Fmt.signed(m.quantity), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: m.isInbound ? AppColors.success : AppColors.danger))),
                ColumnSpec(label: 'Balance', width: 80, numeric: true, cell: (m) => Text(Fmt.number(m.balanceAfter), style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Reason / reference', flex: 2, cell: (m) => Text(m.reason ?? m.referenceType ?? '—', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ColumnSpec(label: 'By', width: 100, cell: (m) => Text(m.createdBy?.name ?? '—', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
