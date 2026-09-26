import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/data_table_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/filter_bar.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/catalog.dart';
import '../controllers/stores_controller.dart';
import '../widgets/store_form_dialog.dart';

class StoresView extends StatelessWidget {
  const StoresView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(StoresController(Get.find(), Get.find()));
    return ShellPage(
      title: 'Stores',
      breadcrumb: 'Catalog',
      headerActions: [
        FilledButton.icon(
          onPressed: () async {
            if (await showStoreFormDialog(managers: c.managers)) c.load();
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New store'),
        ),
      ],
      child: SectionCard(
        padding: EdgeInsets.zero,
        expandChild: true,
        child: Column(children: [
          Obx(() => FilterBar(
                search: SearchField(onChanged: c.setSearch, hint: 'Search stores…'),
                filters: [
                  FilterDropdown<String>(label: 'Status', value: c.filters['status'] as String?, items: const ['ACTIVE', 'INACTIVE'], onChanged: (v) => c.setFilter('status', v)),
                  FilterDropdown<String>(label: 'Manager', value: c.filters['managerId'] as String?, items: c.managers.map((m) => m.id).toList(), itemLabel: (id) => c.managers.firstWhere((m) => m.id == id).name, onChanged: (v) => c.setFilter('managerId', v)),
                  if (c.hasActiveFilters) ClearFiltersButton(onPressed: c.clearFilters),
                ],
              )),
          const Divider(height: 1),
          Expanded(
            child: AppDataTable<StoreModel>(
              controller: c,
              emptyTitle: 'No stores found',
              onRowTap: (s) => Get.toNamed(AppRoutes.store(s.id)),
              columns: [
                ColumnSpec(label: 'Store', sortKey: 'name', flex: 3, cell: (s) => Text(s.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                ColumnSpec(label: 'Code', sortKey: 'code', width: 90, cell: (s) => Text(s.code, style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'City', sortKey: 'city', flex: 2, cell: (s) => Text(s.city ?? '—', style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Email', flex: 2, cell: (s) => Text(s.email ?? '—', style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                ColumnSpec(label: 'Manager', flex: 2, cell: (s) => Text(s.manager?.name ?? 'Unassigned', style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                ColumnSpec(label: 'Users', width: 70, numeric: true, cell: (s) => Text('${s.userCount}', style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Status', sortKey: 'status', width: 100, cell: (s) => StatusBadge(s.status)),
                ColumnSpec(label: 'Created', sortKey: 'createdAt', width: 120, cell: (s) => Text(Fmt.date(s.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
              ],
              rowActions: (s) => PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 18),
                onSelected: (action) async {
                  if (action == 'edit') {
                    if (await showStoreFormDialog(store: s, managers: c.managers)) c.load();
                  } else if (action == 'toggle') {
                    c.toggleStatus(s);
                  } else if (action == 'view') {
                    Get.toNamed(AppRoutes.store(s.id));
                  } else if (action == 'delete') {
                    if (await confirmDialog(title: 'Delete store', message: 'Delete "${s.name}"? Stores with related records are deactivated instead.', confirmLabel: 'Delete', destructive: true)) {
                      c.deleteStore(s);
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'view', child: Text('View details')),
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'toggle', child: Text(s.isActive ? 'Deactivate' : 'Activate')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.danger))),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
