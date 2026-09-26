import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/data_table_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/filter_bar.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/platform.dart';
import '../controllers/audit_logs_controller.dart';

class AuditLogsView extends StatelessWidget {
  const AuditLogsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(AuditLogsController(Get.find()));
    return ShellPage(
      title: 'Audit log',
      breadcrumb: 'Administration',
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
                search: SearchField(onChanged: c.setSearch, hint: 'Search summary, user or record…'),
                filters: [
                  FilterDropdown<String>(label: 'Module', value: c.filters['module'] as String?, items: c.modules, onChanged: (v) => c.setFilter('module', v)),
                  FilterDropdown<String>(label: 'Action', value: c.filters['action'] as String?, items: c.actions, onChanged: (v) => c.setFilter('action', v)),
                  DateRangeFilter(start: c.filters['startDate'] as DateTime?, end: c.filters['endDate'] as DateTime?, onChanged: (s, e) => c.setFilters({'startDate': s, 'endDate': e})),
                  if (c.hasActiveFilters) ClearFiltersButton(onPressed: c.clearFilters),
                ],
              )),
          const Divider(height: 1),
          Expanded(
            child: AppDataTable<AuditLogEntry>(
              controller: c,
              emptyTitle: 'No audit entries found',
              onRowTap: (e) => _showDetail(e),
              columns: [
                ColumnSpec(label: 'Time', sortKey: 'createdAt', width: 150, cell: (e) => Text(Fmt.dateTime(e.createdAt), style: const TextStyle(fontSize: 12))),
                ColumnSpec(label: 'User', flex: 1, cell: (e) => Text(e.userName ?? 'System', style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                ColumnSpec(label: 'Module', sortKey: 'module', width: 110, cell: (e) => Tag(e.module)),
                ColumnSpec(label: 'Action', sortKey: 'action', width: 130, cell: (e) => Tag(e.action, tone: Tone.info)),
                ColumnSpec(label: 'Summary', flex: 3, cell: (e) => Text(e.summary ?? '—', style: const TextStyle(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  void _showDetail(AuditLogEntry e) {
    Get.dialog(AppDialog(
      title: 'Audit entry',
      width: 560,
      child: InfoGrid(columns: 2, items: [
        ('Time', infoText(Fmt.dateTime(e.createdAt))),
        ('User', infoText(e.userName ?? 'System')),
        ('Module', infoText(e.module)),
        ('Action', infoText(e.action)),
        ('Record ID', infoText(e.recordId)),
        ('IP address', infoText(e.ipAddress)),
        ('Summary', infoText(e.summary)),
        if (e.oldValue != null) ('Old value', SelectableText('${e.oldValue}', style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'))),
        if (e.newValue != null) ('New value', SelectableText('${e.newValue}', style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'))),
      ]),
    ));
  }
}
