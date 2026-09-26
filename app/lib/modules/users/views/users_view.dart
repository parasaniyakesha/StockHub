import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/data_table_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/filter_bar.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/repositories.dart';
import '../controllers/users_controller.dart';
import '../widgets/user_form_dialog.dart';

class UsersView extends StatelessWidget {
  const UsersView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(UsersController(Get.find(), Get.find()));
    return ShellPage(
      title: 'Users',
      breadcrumb: 'Administration',
      headerActions: [
        FilledButton.icon(
          onPressed: () async {
            if (await showUserFormDialog(stores: c.stores, managerOnlyStoreUsers: !c.isAdmin)) {
              Toast.success('User created');
              c.load();
            }
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New user'),
        ),
      ],
      child: SectionCard(
        padding: EdgeInsets.zero,
        expandChild: true,
        child: Column(children: [
          Obx(() => FilterBar(
                search: SearchField(onChanged: c.setSearch, hint: 'Search name or email…'),
                filters: [
                  if (c.isAdmin) FilterDropdown<String>(label: 'Role', value: c.filters['role'] as String?, items: const ['ADMIN', 'MANAGER', 'STORE'], onChanged: (v) => c.setFilter('role', v)),
                  FilterDropdown<String>(label: 'Store', value: c.filters['storeId'] as String?, items: c.stores.map((s) => s.id).toList(), itemLabel: (id) => c.stores.firstWhere((s) => s.id == id).name, onChanged: (v) => c.setFilter('storeId', v)),
                  FilterDropdown<String>(label: 'Status', value: c.filters['status'] as String?, items: const ['ACTIVE', 'INACTIVE'], onChanged: (v) => c.setFilter('status', v)),
                  if (c.hasActiveFilters) ClearFiltersButton(onPressed: c.clearFilters),
                ],
              )),
          const Divider(height: 1),
          Expanded(
            child: AppDataTable<AppUser>(
              controller: c,
              emptyTitle: 'No users found',
              columns: [
                ColumnSpec(label: 'Name', sortKey: 'name', flex: 2, cell: (u) => Row(children: [
                      InitialsAvatar(Fmt.initials(u.name), size: 26),
                      const SizedBox(width: 8),
                      Expanded(child: Text(u.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                    ])),
                ColumnSpec(label: 'Email', sortKey: 'email', flex: 2, cell: (u) => Text(u.email, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                ColumnSpec(label: 'Role', width: 110, cell: (u) => StatusBadge(u.role, label: u.roleLabel, dense: true)),
                ColumnSpec(label: 'Store', flex: 1, cell: (u) => Text(u.store?.name ?? '—', style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                ColumnSpec(label: 'Last login', width: 120, cell: (u) => Text(Fmt.relative(u.lastLoginAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                ColumnSpec(label: 'Status', sortKey: 'status', width: 100, cell: (u) => StatusBadge(u.status)),
              ],
              rowActions: (u) => PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 18),
                onSelected: (action) async {
                  if (action == 'edit') {
                    if (await showUserFormDialog(user: u, stores: c.stores)) c.load();
                  } else if (action == 'toggle') {
                    c.toggleStatus(u);
                  } else if (action == 'reset') {
                    final password = await reasonDialog(title: 'Reset password', label: 'New temporary password', message: 'The user must sign in again after this.', confirmLabel: 'Reset');
                    if (password != null) {
                      try {
                        await Get.find<UserRepository>().resetPassword(u.id, password);
                        Toast.success('Password reset');
                      } catch (e) {
                        Toast.fromError(e);
                      }
                    }
                  } else if (action == 'delete') {
                    if (await confirmDialog(title: 'Delete user', message: 'Delete "${u.name}"? Accounts with activity history are deactivated instead.', confirmLabel: 'Delete', destructive: true)) {
                      c.deleteUser(u);
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'toggle', child: Text(u.isActive ? 'Deactivate' : 'Activate')),
                  const PopupMenuItem(value: 'reset', child: Text('Reset password')),
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
