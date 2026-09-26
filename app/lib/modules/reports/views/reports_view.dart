import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/filter_bar.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/platform.dart';
import '../controllers/reports_controller.dart';

class ReportsView extends StatelessWidget {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(ReportsController(Get.find(), Get.find(), Get.find()));
    return ShellPage(
      title: 'Reports',
      breadcrumb: 'Sales',
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
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _KindTabs(c: c),
          const SizedBox(height: Gap.lg),
          Expanded(
            child: SectionCard(
              padding: EdgeInsets.zero,
              expandChild: true,
              child: Column(children: [
                Obx(() => FilterBar(filters: [
                      _TypeDropdown(c: c),
                      if (!c.isStore)
                        FilterDropdown<String>(label: 'Store', value: c.storeId.value, items: c.stores.map((s) => s.id).toList(), itemLabel: (id) => c.stores.firstWhere((s) => s.id == id).name, onChanged: c.setStore),
                      if (c.kind.value == ReportKind.stock || c.kind.value == ReportKind.sales)
                        FilterDropdown<String>(label: 'Category', value: c.categoryId.value, items: c.categories.map((cat) => cat.id).toList(), itemLabel: (id) => c.categories.firstWhereOrNull((cat) => cat.id == id)?.displayName ?? '', onChanged: c.setCategory),
                      DateRangeFilter(start: c.startDate.value, end: c.endDate.value, onChanged: c.setDateRange),
                    ])),
                const Divider(height: 1),
                Expanded(
                  child: Obx(() {
                    if (c.loading.value) return const LoadingView();
                    if (c.errorMessage.value != null) return ErrorView(message: c.errorMessage.value!, onRetry: c.load);
                    final report = c.report.value;
                    if (report == null || report.rows.isEmpty) return const EmptyView(icon: Icons.insights_outlined, title: 'No data for this report');
                    return _ReportTable(report: report);
                  }),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _KindTabs extends StatelessWidget {
  const _KindTabs({required this.c});
  final ReportsController c;

  @override
  Widget build(BuildContext context) {
    final items = [
      (ReportKind.sales, 'Sales'),
      (ReportKind.stock, 'Stock'),
      (ReportKind.operations, 'Operations'),
      if (!c.isStore) (ReportKind.stores, 'Stores'),
    ];
    return Obx(() => Wrap(spacing: Gap.sm, children: [
          for (final (value, label) in items) ChoiceChip(label: Text(label), selected: c.kind.value == value, onSelected: (_) => c.setKind(value)),
        ]));
  }
}

class _TypeDropdown extends StatelessWidget {
  const _TypeDropdown({required this.c});
  final ReportsController c;

  @override
  Widget build(BuildContext context) {
    final options = switch (c.kind.value) { ReportKind.stock => stockReportTypes, ReportKind.sales => salesGroupings, ReportKind.operations => operationsReportTypes, _ => const <String>[] };
    if (options.isEmpty) return const SizedBox();
    return FilterDropdown<String>(
      label: c.kind.value == ReportKind.sales ? 'Group by' : 'Type',
      value: c.type.value,
      items: options,
      itemLabel: (v) => Fmt.enumLabel(v.replaceAll('-', '_')),
      onChanged: (v) => c.setType(v ?? options.first),
      allLabel: options.first,
    );
  }
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({required this.report});
  final ReportData report;

  String _fmt(ReportColumn col, Map<String, dynamic> row) {
    final v = row[col.key];
    if (v == null) return '—';
    switch (col.type) {
      case 'money':
        return Fmt.money(v is num ? v : double.tryParse('$v'));
      case 'number':
        return Fmt.number(v is num ? v : double.tryParse('$v'));
      case 'date':
        return Fmt.date(DateTime.tryParse('$v'));
      case 'datetime':
        return Fmt.dateTime(DateTime.tryParse('$v'));
      default:
        return '$v';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: 42,
          dataRowMaxHeight: 46,
          columnSpacing: 20,
          columns: [for (final col in report.columns) DataColumn(label: Text(col.label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)), numeric: col.isNumeric)],
          rows: [
            for (final row in report.rows)
              DataRow(cells: [
                for (final col in report.columns)
                  DataCell(col.type == 'status'
                      ? StatusBadge('${row[col.key]}', dense: true)
                      : SizedBox(width: 160, child: Text(_fmt(col, row), style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis))),
              ]),
          ],
        ),
      ),
    );
  }
}
