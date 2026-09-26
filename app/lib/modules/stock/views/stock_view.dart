import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/data_table_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/filter_bar.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/stock.dart';
import '../controllers/stock_controller.dart';
import '../widgets/stock_entry_dialog.dart';

class StockView extends StatelessWidget {
  const StockView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(StockController(Get.find(), Get.find(), Get.find(), Get.find()));
    return ShellPage(
      title: 'Stock',
      breadcrumb: 'Inventory',
      headerActions: [
        if (c.isAdmin) ...[
          OutlinedButton.icon(
            onPressed: () async {
              if (await showStockEntryDialog(mode: StockEntryMode.opening, isWarehouse: c.locationType == 'WAREHOUSE', warehouses: c.warehouses, stores: c.stores)) {
                Toast.success('Opening stock recorded');
                c.load();
              }
            },
            icon: const Icon(Icons.playlist_add_outlined, size: 16),
            label: const Text('Opening stock'),
          ),
          const SizedBox(width: Gap.sm),
          OutlinedButton.icon(
            onPressed: () async {
              if (await showStockEntryDialog(mode: StockEntryMode.purchase, isWarehouse: true, warehouses: c.warehouses)) {
                Toast.success('Purchase recorded');
                c.load();
              }
            },
            icon: const Icon(Icons.shopping_cart_outlined, size: 16),
            label: const Text('Purchase'),
          ),
          const SizedBox(width: Gap.sm),
        ],
        Obx(() {
          final canAdjust = Get.find<AuthService>().can('stock.adjust');
          if (!canAdjust) return const SizedBox();
          return OutlinedButton.icon(
            onPressed: () async {
              if (await showStockEntryDialog(mode: StockEntryMode.adjustment, isWarehouse: c.locationType == 'WAREHOUSE', warehouses: c.warehouses, stores: c.stores)) {
                Toast.success('Stock adjusted');
                c.load();
              }
            },
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('Adjust'),
          );
        }),
        const SizedBox(width: Gap.sm),
        FilledButton.icon(
          onPressed: () async {
            if (await showStockEntryDialog(mode: StockEntryMode.damage, isWarehouse: c.locationType == 'WAREHOUSE', warehouses: c.warehouses, stores: c.stores)) {
              Toast.success('Damage reported');
              c.load();
            }
          },
          icon: const Icon(Icons.report_problem_outlined, size: 16),
          label: const Text('Report damage'),
        ),
      ],
      child: SectionCard(
        padding: EdgeInsets.zero,
        expandChild: true,
        child: Column(children: [
          Obx(() => FilterBar(
                search: SearchField(onChanged: c.setSearch, hint: 'Search products…'),
                filters: [
                  if (!c.isStore)
                    ChoiceChip(label: const Text('Stores'), selected: c.locationType == 'STORE', onSelected: (_) => c.setLocationType('STORE')),
                  if (!c.isStore)
                    ChoiceChip(label: const Text('Warehouse'), selected: c.locationType == 'WAREHOUSE', onSelected: (_) => c.setLocationType('WAREHOUSE')),
                  if (c.locationType == 'STORE' && c.stores.isNotEmpty)
                    FilterDropdown<String>(label: 'Store', value: c.filters['storeId'] as String?, items: c.stores.map((s) => s.id).toList(), itemLabel: (id) => c.stores.firstWhere((s) => s.id == id).name, onChanged: (v) => c.setFilter('storeId', v)),
                  FilterDropdown<String>(label: 'Category', value: c.filters['categoryId'] as String?, items: c.categories.map((cat) => cat.id).toList(), itemLabel: (id) => c.categories.firstWhereOrNull((cat) => cat.id == id)?.displayName ?? '', onChanged: (v) => c.setFilter('categoryId', v)),
                  FilterDropdown<bool>(label: 'Low stock', value: c.filters['lowStock'] as bool?, items: const [true], itemLabel: (_) => 'Low stock only', onChanged: (v) => c.setFilter('lowStock', v)),
                  FilterDropdown<bool>(label: 'Hide zero', value: c.filters['hideZero'] as bool?, items: const [true], itemLabel: (_) => 'Hide zero balances', onChanged: (v) => c.setFilter('hideZero', v)),
                  if (c.hasActiveFilters) ClearFiltersButton(onPressed: c.clearFilters),
                ],
              )),
          const Divider(height: 1),
          Expanded(
            child: AppDataTable<StockBalance>(
              controller: c,
              emptyTitle: 'No stock records found',
              columns: [
                ColumnSpec(label: 'Product', sortKey: 'product', flex: 3, cell: (b) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.product.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(b.product.sku, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ])),
                ColumnSpec(label: 'Location', flex: 2, cell: (b) => Text(b.location.name, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                ColumnSpec(label: 'On hand', sortKey: 'quantity', width: 90, numeric: true, cell: (b) => Text(Fmt.number(b.quantity), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: b.isLow ? AppColors.danger : AppColors.textPrimary))),
                ColumnSpec(label: 'Reserved', width: 90, numeric: true, cell: (b) => Text(Fmt.number(b.reservedQuantity), style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted))),
                ColumnSpec(label: 'Available', width: 90, numeric: true, cell: (b) => Text(Fmt.number(b.availableQuantity), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                ColumnSpec(label: 'Damaged', sortKey: 'damaged', width: 90, numeric: true, cell: (b) => b.damagedQuantity > 0 ? Tag('${b.damagedQuantity}', tone: Tone.danger) : const Text('—', style: TextStyle(fontSize: 12, color: AppColors.textMuted))),
                ColumnSpec(label: '', width: 80, cell: (b) => b.isLow ? const StatusBadge('LOW', label: 'Low', dense: true) : const SizedBox()),
              ],
              rowActions: (b) => PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 18),
                onSelected: (action) async {
                  if (action == 'movements') {
                    Get.toNamed('${AppRoutes.stockMovements}?productId=${b.product.id}');
                  } else if (action == 'writeoff') {
                    final storeModel = c.stores.firstWhereOrNull((s) => s.id == b.location.id);
                    if (await showStockEntryDialog(mode: StockEntryMode.writeOff, isWarehouse: c.locationType == 'WAREHOUSE', warehouses: c.warehouses, stores: storeModel == null ? const [] : [storeModel], storeId: storeModel?.id, warehouseId: c.locationType == 'WAREHOUSE' ? b.location.id : null)) {
                      Toast.success('Damaged stock written off');
                      c.load();
                    }
                  } else if (action == 'delete') {
                    if (await confirmDialog(title: 'Remove stock record', message: 'Remove this empty record for "${b.product.name}" at ${b.location.name}? The stock movement history stays intact.', confirmLabel: 'Remove', destructive: true)) {
                      c.deleteBalance(b);
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'movements', child: Text('View movements')),
                  if (c.isAdmin && b.damagedQuantity > 0) const PopupMenuItem(value: 'writeoff', child: Text('Write off damaged')),
                  if (b.quantity == 0 && b.reservedQuantity == 0 && b.damagedQuantity == 0)
                    const PopupMenuItem(value: 'delete', child: Text('Remove record', style: TextStyle(color: AppColors.danger))),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
