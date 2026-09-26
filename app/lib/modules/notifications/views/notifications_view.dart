import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/base/paged_list_controller.dart';
import '../../../core/network/api_response.dart';
import '../../../core/session/notification_center.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/data_table_view.dart';
import '../../../data/models/platform.dart';
import '../../../data/repositories/repositories.dart';

class NotificationsListController extends PagedListController<AppNotification> {
  NotificationsListController(this._repo) : super(tableId: 'notifications', initialSortBy: 'createdAt', initialSortAsc: false);
  final PlatformRepository _repo;

  @override
  Future<PageResult<AppNotification>> fetchPage(ListQuery query) => _repo.notifications(query);

  @override
  String idOf(AppNotification item) => item.id;

  Future<void> markRead(AppNotification n) async {
    if (n.isRead) return;
    await Get.find<NotificationCenter>().markRead(n);
    final i = items.indexWhere((x) => x.id == n.id);
    if (i >= 0) items[i] = n.markRead();
  }
}

class NotificationsView extends StatelessWidget {
  const NotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(NotificationsListController(Get.find()));
    return ShellPage(
      title: 'Notifications',
      breadcrumb: 'Overview',
      headerActions: [
        OutlinedButton.icon(
          onPressed: () async {
            await Get.find<NotificationCenter>().markAllRead();
            c.load();
          },
          icon: const Icon(Icons.done_all, size: 16),
          label: const Text('Mark all read'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: SectionCard(
          padding: EdgeInsets.zero,
          expandChild: true,
          child: AppDataTable<AppNotification>(
            controller: c,
            emptyTitle: 'No notifications yet',
            rowHeight: 58,
            onRowTap: c.markRead,
            columns: [
              ColumnSpec(
                label: '',
                width: 24,
                cell: (n) => n.isRead ? const SizedBox() : Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
              ),
              ColumnSpec(
                label: 'Notification',
                flex: 4,
                cell: (n) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(n.title, style: TextStyle(fontSize: 13, fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(n.message, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              ColumnSpec(label: 'Date', width: 150, cell: (n) => Text(Fmt.dateTime(n.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
            ],
          ),
        ),
      ),
    );
  }
}
