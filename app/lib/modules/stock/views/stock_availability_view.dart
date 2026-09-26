import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/quantity_lines_editor.dart';
import '../../../core/widgets/state_views.dart';
import '../controllers/stock_availability_controller.dart';

class StockAvailabilityView extends StatelessWidget {
  const StockAvailabilityView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(StockAvailabilityController(Get.find()));
    return ShellPage(
      title: 'Store availability',
      breadcrumb: 'Inventory',
      child: c.isAdmin ? _MatrixView(c: c) : _SubmitView(c: c),
    );
  }
}

/// Store view: submit what is physically on the shelf right now.
class _SubmitView extends StatelessWidget {
  const _SubmitView({required this.c});
  final StockAvailabilityController c;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Gap.xl),
      child: SectionCard(
        title: 'Submit available quantities',
        subtitle: 'Tell head office what is physically available in your store right now. This does not change your recorded stock.',
        child: Obx(() {
          if (c.loadingMine.value) return const LoadingView();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            QuantityLinesEditor(lines: c.lines, onChanged: (_) {}, emptyHint: 'Add the products you want to declare quantities for.'),
            const SizedBox(height: Gap.lg),
            Align(
              alignment: Alignment.centerRight,
              child: Obx(() => FilledButton.icon(
                    onPressed: c.submitting.value ? null : () => c.submit(null),
                    icon: c.submitting.value ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check, size: 16),
                    label: const Text('Submit'),
                  )),
            ),
          ]);
        }),
      ),
    );
  }
}

/// Admin/manager view: cross-store comparison (declared vs. system stock).
class _MatrixView extends StatelessWidget {
  const _MatrixView({required this.c});
  final StockAvailabilityController c;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Gap.xl),
      child: SectionCard(
        title: 'Availability across stores',
        subtitle: 'Declared (self-reported) vs. system stock, per store. Use this to spot inter-store transfer opportunities.',
        expandChild: true,
        child: Obx(() {
          if (c.matrixLoading.value) return const LoadingView();
          if (c.matrixError.value != null) return ErrorView(message: c.matrixError.value!, onRetry: c.loadMatrix);
          final m = c.matrix.value;
          if (m == null || m.rows.isEmpty) return const EmptyView(icon: Icons.fact_check_outlined, title: 'No availability data yet');
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 44,
              columnSpacing: 20,
              columns: [
                const DataColumn(label: Text('Product', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600))),
                for (final s in m.stores) DataColumn(label: Text(s.name, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)), numeric: true),
                const DataColumn(label: Text('Total declared', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)), numeric: true),
                const DataColumn(label: Text('Total system', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)), numeric: true),
              ],
              rows: [
                for (final row in m.rows)
                  DataRow(cells: [
                    DataCell(SizedBox(width: 160, child: Text(row.product.name, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis))),
                    for (final s in m.stores)
                      DataCell(_Cell(row.cellFor(s.id))),
                    DataCell(Text('${row.totalDeclared}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                    DataCell(Text('${row.totalSystem}', style: const TextStyle(fontSize: 12.5))),
                  ]),
              ],
            ),
            ),
          );
        }),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.cell);
  final dynamic cell;

  @override
  Widget build(BuildContext context) {
    if (cell == null) return const Text('—', style: TextStyle(fontSize: 12, color: AppColors.textMuted));
    final declared = cell.declaredQuantity;
    final system = cell.systemQuantity as int;
    final mismatch = declared != null && declared != system;
    return Text(
      declared == null ? '($system)' : '$declared',
      style: TextStyle(fontSize: 12.5, fontWeight: mismatch ? FontWeight.w700 : FontWeight.w500, color: mismatch ? AppColors.warning : AppColors.textPrimary),
    );
  }
}
