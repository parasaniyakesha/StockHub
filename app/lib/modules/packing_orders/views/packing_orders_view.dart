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
import '../../../data/models/operations.dart';
import '../controllers/packing_orders_controller.dart';

class PackingOrdersView extends StatelessWidget {
  const PackingOrdersView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(PackingOrdersController(Get.find(), Get.find()));
    return ShellPage(
      title: 'Packing orders',
      breadcrumb: 'Operations',
      headerActions: [
        if (c.canManage) FilledButton.icon(onPressed: () => Get.toNamed(AppRoutes.packingNew), icon: const Icon(Icons.add, size: 18), label: const Text('New packing order')),
      ],
      child: SectionCard(
        padding: EdgeInsets.zero,
        expandChild: true,
        child: Column(children: [
          Obx(() => FilterBar(
                search: SearchField(onChanged: c.setSearch, hint: 'Search order # or store…'),
                filters: [
                  if (!c.isStore && c.stores.isNotEmpty)
                    FilterDropdown<String>(label: 'Store', value: c.filters['storeId'] as String?, items: c.stores.map((s) => s.id).toList(), itemLabel: (id) => c.stores.firstWhere((s) => s.id == id).name, onChanged: (v) => c.setFilter('storeId', v)),
                  FilterDropdown<String>(label: 'Status', value: c.filters['status'] as String?, items: PackingStatus.all, onChanged: (v) => c.setFilter('status', v)),
                  if (c.hasActiveFilters) ClearFiltersButton(onPressed: c.clearFilters),
                ],
              )),
          const Divider(height: 1),
          Expanded(
            child: AppDataTable<PackingOrder>(
              controller: c,
              emptyTitle: 'No packing orders found',
              onRowTap: (o) => Get.toNamed(AppRoutes.packingOrder(o.id)),
              columns: [
                ColumnSpec(label: 'Order #', sortKey: 'orderNumber', width: 110, cell: (o) => Text(o.orderNumber, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                ColumnSpec(label: 'Stores', width: 200, flex: 2, cell: (o) => Text(o.stores.map((s) => s.store.name).join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Items', width: 70, numeric: true, cell: (o) => Text('${o.itemCount}', style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Allocated', width: 90, numeric: true, cell: (o) => Text(Fmt.number(o.totalAllocated), style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Dispatched', width: 90, numeric: true, cell: (o) => Text(Fmt.number(o.totalDispatched), style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Received', width: 90, numeric: true, cell: (o) => Text(Fmt.number(o.totalReceived), style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Status', sortKey: 'status', width: 120, cell: (o) => StatusBadge(o.status)),
                ColumnSpec(label: 'Created', sortKey: 'createdAt', width: 140, cell: (o) => Text(Fmt.dateTime(o.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
