import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
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
import '../../../data/models/catalog.dart';
import '../controllers/products_controller.dart';
import '../widgets/product_form_dialog.dart';

class ProductsView extends StatelessWidget {
  const ProductsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(ProductsController(Get.find(), Get.find()));
    return ShellPage(
      title: 'Products',
      breadcrumb: 'Catalog',
      headerActions: [
        if (c.canManage) ...[
          Obx(() => OutlinedButton.icon(
                onPressed: c.importing.value ? null : c.importCsv,
                icon: const Icon(Icons.upload_file_outlined, size: 16),
                label: const Text('Import'),
              )),
          const SizedBox(width: Gap.sm),
        ],
        _ExportButton(c: c),
        if (c.canManage) ...[
          const SizedBox(width: Gap.sm),
          FilledButton.icon(
            onPressed: () async {
              final saved = await showProductFormDialog(categories: c.categories);
              if (saved != null) {
                Toast.success('Product created');
                c.load();
              }
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New product'),
          ),
        ],
      ],
      child: SectionCard(
        padding: EdgeInsets.zero,
        expandChild: true,
        child: Column(children: [
          Obx(() => FilterBar(
                search: SearchField(onChanged: c.setSearch, hint: 'Search by name, SKU or barcode…'),
                filters: [
                  FilterDropdown<String>(
                    label: 'Category',
                    value: c.filters['categoryId'] as String?,
                    items: c.categories.map((cat) => cat.id).toList(),
                    itemLabel: (id) => c.categories.firstWhereOrNull((cat) => cat.id == id)?.displayName ?? '',
                    onChanged: (v) => c.setFilter('categoryId', v),
                  ),
                  if (!c.isStore)
                    FilterDropdown<String>(label: 'Status', value: c.filters['status'] as String?, items: const ['ACTIVE', 'INACTIVE'], onChanged: (v) => c.setFilter('status', v)),
                  FilterDropdown<bool>(label: 'Stock', value: c.filters['lowStock'] as bool?, items: const [true], itemLabel: (_) => 'Low stock only', onChanged: (v) => c.setFilter('lowStock', v), allLabel: 'All stock levels'),
                  if (c.hasActiveFilters) ClearFiltersButton(onPressed: c.clearFilters),
                ],
              )),
          const Divider(height: 1),
          Expanded(
            child: AppDataTable<Product>(
              controller: c,
              emptyTitle: 'No products found',
              emptyMessage: 'Try adjusting your search or filters, or add a new product.',
              onRowTap: (p) => Get.toNamed(AppRoutes.product(p.id)),
              columns: [
                ColumnSpec(label: 'Product', sortKey: 'name', flex: 3, cell: (p) => _ProductCell(p)),
                ColumnSpec(label: 'SKU', sortKey: 'sku', width: 110, cell: (p) => Text(p.sku, style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Category', sortKey: 'category', flex: 2, cell: (p) => Text(p.category?.name ?? '—', style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                ColumnSpec(label: 'Stock', width: 90, numeric: true, cell: (p) => _StockCell(p)),
                ColumnSpec(label: 'Price', sortKey: 'sellingPrice', width: 100, numeric: true, cell: (p) => Text(Fmt.money(p.sellingPrice), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                ColumnSpec(label: 'Status', sortKey: 'status', width: 100, cell: (p) => StatusBadge(p.status)),
              ],
              rowActions: c.canManage
                  ? (p) => PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz, size: 18),
                        onSelected: (action) async {
                          if (action == 'edit') {
                            final saved = await showProductFormDialog(product: p, categories: c.categories);
                            if (saved != null) c.load();
                          } else if (action == 'toggle') {
                            c.toggleStatus(p);
                          } else if (action == 'delete') {
                            if (await confirmDialog(title: 'Delete product', message: 'Delete "${p.name}"? Products with stock history are deactivated instead.', confirmLabel: 'Delete', destructive: true)) {
                              c.deleteProduct(p);
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'toggle', child: Text(p.isActive ? 'Deactivate' : 'Activate')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.danger))),
                        ],
                      )
                  : null,
            ),
          ),
        ]),
      ),
    );
  }
}

class _ProductCell extends StatelessWidget {
  const _ProductCell(this.p);
  final Product p;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: AppColors.neutralSoft, borderRadius: BorderRadius.circular(6)),
        child: const Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.textMuted),
      ),
      const SizedBox(width: Gap.sm),
      Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
    ]);
  }
}

class _StockCell extends StatelessWidget {
  const _StockCell(this.p);
  final Product p;
  @override
  Widget build(BuildContext context) {
    final low = p.minimumStock > 0 && p.displayStock <= p.minimumStock;
    return Text(Fmt.number(p.displayStock), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: low ? AppColors.danger : AppColors.textPrimary));
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.c});
  final ProductsController c;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
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
              c.exporting.value
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_outlined, size: 16),
              const SizedBox(width: 8),
              const Text('Export', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          )),
    );
  }
}
