import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/data_table_view.dart';
import '../../../core/widgets/filter_bar.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/operations.dart';
import '../controllers/transfers_controller.dart';

class TransfersView extends StatelessWidget {
  const TransfersView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(TransfersController(Get.find(), Get.find()));
    final auth = Get.find<AuthService>();
    return ShellPage(
      title: 'Stock transfers',
      breadcrumb: 'Operations',
      headerActions: [
        if (auth.can('transfers.request'))
          FilledButton.icon(onPressed: () => Get.toNamed(AppRoutes.transferNew), icon: const Icon(Icons.add, size: 18), label: const Text('New transfer')),
      ],
      child: SectionCard(
        padding: EdgeInsets.zero,
        expandChild: true,
        child: Column(children: [
          Obx(() => FilterBar(
                search: SearchField(onChanged: c.setSearch, hint: 'Search transfer # or store…'),
                filters: [
                  if (!c.isStore && c.stores.isNotEmpty)
                    FilterDropdown<String>(label: 'Store', value: c.filters['storeId'] as String?, items: c.stores.map((s) => s.id).toList(), itemLabel: (id) => c.stores.firstWhere((s) => s.id == id).name, onChanged: (v) => c.setFilter('storeId', v)),
                  if (c.isStore) FilterDropdown<String>(label: 'Direction', value: c.filters['direction'] as String?, items: const ['IN', 'OUT'], onChanged: (v) => c.setFilter('direction', v)),
                  FilterDropdown<String>(label: 'Source', value: c.filters['sourceType'] as String?, items: const ['WAREHOUSE', 'STORE'], onChanged: (v) => c.setFilter('sourceType', v)),
                  FilterDropdown<String>(label: 'Status', value: c.filters['status'] as String?, items: TransferStatus.all, onChanged: (v) => c.setFilter('status', v)),
                  if (c.hasActiveFilters) ClearFiltersButton(onPressed: c.clearFilters),
                ],
              )),
          const Divider(height: 1),
          Expanded(
            child: AppDataTable<StockTransfer>(
              controller: c,
              emptyTitle: 'No transfers found',
              onRowTap: (t) => Get.toNamed(AppRoutes.transfer(t.id)),
              columns: [
                ColumnSpec(label: 'Transfer #', sortKey: 'transferNumber', width: 120, cell: (t) => Text(t.transferNumber, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                ColumnSpec(label: 'From', flex: 2, cell: (t) => Text(t.source.name, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                ColumnSpec(label: 'To', flex: 2, cell: (t) => Text(t.toStore.name, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                ColumnSpec(label: 'Items', width: 70, numeric: true, cell: (t) => Text('${t.itemCount}', style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Requested', width: 90, numeric: true, cell: (t) => Text(Fmt.number(t.totalRequested), style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Status', sortKey: 'status', width: 120, cell: (t) => StatusBadge(t.status)),
                ColumnSpec(label: 'Created', sortKey: 'createdAt', width: 140, cell: (t) => Text(Fmt.dateTime(t.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
