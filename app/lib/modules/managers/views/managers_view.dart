import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/data_table_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/filter_bar.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/user.dart';
import '../../users/widgets/user_form_dialog.dart';
import '../controllers/managers_controller.dart';
import '../widgets/manager_dialogs.dart';

class ManagersView extends StatelessWidget {
  const ManagersView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(ManagersController(Get.find(), Get.find()));
    return ShellPage(
      title: 'Managers',
      breadcrumb: 'Administration',
      headerActions: [
        FilledButton.icon(
          onPressed: () async {
            if (await showUserFormDialog(stores: c.stores)) {
              Toast.success('Manager created');
              c.load();
            }
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New manager'),
        ),
      ],
      child: SectionCard(
        padding: EdgeInsets.zero,
        expandChild: true,
        child: Column(children: [
          FilterBar(search: SearchField(onChanged: c.setSearch, hint: 'Search managers…')),
          const Divider(height: 1),
          Expanded(
            child: AppDataTable<AppUser>(
              controller: c,
              emptyTitle: 'No managers found',
              columns: [
                ColumnSpec(label: 'Name', sortKey: 'name', flex: 2, cell: (m) => Text(m.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                ColumnSpec(label: 'Email', flex: 2, cell: (m) => Text(m.email, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                ColumnSpec(label: 'Assigned stores', flex: 2, cell: (m) => Text(m.managedStores.isEmpty ? 'None' : m.managedStores.map((s) => s.code).join(', '), style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                ColumnSpec(label: 'Permissions', width: 100, numeric: true, cell: (m) => Text('${m.permissions.length}', style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Status', width: 100, cell: (m) => StatusBadge(m.status)),
              ],
              rowActions: (m) => PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 18),
                onSelected: (action) async {
                  if (action == 'stores') {
                    final ids = await showAssignStoresDialog(m, c.stores);
                    if (ids != null) c.setStores(m.id, ids);
                  } else if (action == 'permissions') {
                    final perms = await showManagerPermissionsDialog(m);
                    if (perms != null) c.setPermissions(m.id, perms);
                  } else if (action == 'edit') {
                    if (await showUserFormDialog(user: m, stores: c.stores)) c.load();
                  } else if (action == 'delete') {
                    if (await confirmDialog(
                      title: 'Delete manager',
                      message: 'Delete "${m.name}"? Managers with activity history are deactivated instead. If they still have stores assigned, reassign those first.',
                      confirmLabel: 'Delete',
                      destructive: true,
                    )) {
                      c.deleteManager(m);
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'stores', child: Text('Assign stores')),
                  const PopupMenuItem(value: 'permissions', child: Text('Permissions')),
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
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
