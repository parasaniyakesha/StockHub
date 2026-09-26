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
import '../controllers/requests_controller.dart';

class RequestsView extends StatelessWidget {
  const RequestsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(RequestsController(Get.find(), Get.find()));
    final auth = Get.find<AuthService>();
    return ShellPage(
      title: 'Product requests',
      breadcrumb: 'Operations',
      headerActions: [
        if (auth.can('requests.create'))
          FilledButton.icon(onPressed: () => Get.toNamed(AppRoutes.requestNew), icon: const Icon(Icons.add, size: 18), label: const Text('New request')),
      ],
      child: SectionCard(
        padding: EdgeInsets.zero,
        expandChild: true,
        child: Column(children: [
          Obx(() => FilterBar(
                search: SearchField(onChanged: c.setSearch, hint: 'Search request # or store…'),
                filters: [
                  if (!c.isStore && c.stores.isNotEmpty)
                    FilterDropdown<String>(label: 'Store', value: c.filters['storeId'] as String?, items: c.stores.map((s) => s.id).toList(), itemLabel: (id) => c.stores.firstWhere((s) => s.id == id).name, onChanged: (v) => c.setFilter('storeId', v)),
                  FilterDropdown<String>(label: 'Status', value: c.filters['status'] as String?, items: RequestStatus.all, onChanged: (v) => c.setFilter('status', v)),
                  DateRangeFilter(start: c.filters['startDate'] as DateTime?, end: c.filters['endDate'] as DateTime?, onChanged: (s, e) => c.setFilters({'startDate': s, 'endDate': e})),
                  if (c.hasActiveFilters) ClearFiltersButton(onPressed: c.clearFilters),
                ],
              )),
          const Divider(height: 1),
          Expanded(
            child: AppDataTable<ProductRequest>(
              controller: c,
              emptyTitle: 'No product requests found',
              onRowTap: (r) => Get.toNamed(AppRoutes.request(r.id)),
              columns: [
                ColumnSpec(label: 'Request #', sortKey: 'requestNumber', width: 120, cell: (r) => Text(r.requestNumber, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                ColumnSpec(label: 'Store', sortKey: 'store', flex: 2, cell: (r) => Text(r.store.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                ColumnSpec(label: 'Items', width: 70, numeric: true, cell: (r) => Text('${r.itemCount}', style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Requested', width: 90, numeric: true, cell: (r) => Text(Fmt.number(r.totalRequested), style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Approved', width: 90, numeric: true, cell: (r) => Text(r.totalApproved == null ? '—' : Fmt.number(r.totalApproved), style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Status', sortKey: 'status', width: 130, cell: (r) => StatusBadge(r.status)),
                ColumnSpec(label: 'Created', sortKey: 'createdAt', width: 140, cell: (r) => Text(Fmt.dateTime(r.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
