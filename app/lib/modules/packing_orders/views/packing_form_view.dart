import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/product_picker.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/store_picker.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/operations.dart';
import '../controllers/packing_form_controller.dart';
import '../widgets/allocate_product_dialog.dart';
import '../widgets/store_products_dialog.dart';

class PackingFormView extends StatelessWidget {
  const PackingFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final editing = Get.arguments as PackingOrder?;
    final c = Get.put(PackingFormController(Get.find(), Get.find(), Get.find(), editing: editing));
    return ShellPage(
      title: editing == null ? 'New packing order' : 'Edit packing order ${editing.orderNumber}',
      breadcrumb: 'Operations / Packing',
      child: Obx(() {
        if (c.loading.value) return const LoadingView();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionCard(
              title: 'Order details',
              child: FormColumn(children: [
                FieldRow(children: [
                  Obx(() => AppDropdownField<String>(label: 'Warehouse', required: true, value: c.warehouseId.value, items: c.warehouses.map((w) => w.id).toList(), itemLabel: (id) => c.warehouses.firstWhere((w) => w.id == id).name, onChanged: (v) => c.warehouseId.value = v)),
                ]),
                TextFormField(initialValue: c.notes.value, decoration: const InputDecoration(labelText: 'Notes (optional)'), maxLines: 2, maxLength: 1000, onChanged: (v) => c.notes.value = v),
              ]),
            ),
            const SizedBox(height: Gap.lg),
            SectionCard(
              title: 'Products to pack',
              subtitle: 'The total planned quantity for each product across all stores.',
              child: Obx(() {
                c.version.value;
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (c.products.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(Gap.lg),
                      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(Radii.md)),
                      child: const Center(child: Text('Add the products you plan to pack.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted))),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(Radii.md)),
                      child: Column(children: [
                        for (var i = 0; i < c.products.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(c.products[i].product.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                  Text(c.products[i].product.sku, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                ]),
                              ),
                              Text('Allocated: ${c.allocatedFor(c.products[i].product.id)}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                              const SizedBox(width: Gap.md),
                              QuantityInput(value: c.products[i].quantity, onChanged: (v) => c.setPlannedQuantity(c.products[i].product.id, v), min: 0),
                              IconButton(
                                icon: const Icon(Icons.storefront_outlined, size: 16),
                                tooltip: 'Allocate to stores',
                                onPressed: () => showAllocateProductDialog(c, c.products[i]),
                              ),
                              IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => c.removeProduct(c.products[i].product.id)),
                            ]),
                          ),
                        ],
                      ]),
                    ),
                  const SizedBox(height: Gap.sm),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await pickProductDialog(exclude: c.products.map((p) => p.product.id).toSet());
                      if (picked != null) c.addProduct(picked);
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add product'),
                  ),
                ]);
              }),
            ),
            const SizedBox(height: Gap.lg),
            SectionCard(
              title: 'Allocate to stores',
              subtitle: 'Enter how much of each product goes to each store. Remaining must reach zero before assigning.',
              child: Obx(() {
                c.version.value;
                if (c.products.isEmpty) return const EmptyView(compact: true, icon: Icons.storefront_outlined, title: 'Add products first');
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (c.selectedStoreIds.isNotEmpty) _AllocationMatrix(c: c),
                  const SizedBox(height: Gap.sm),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await pickStoreDialog(c.allStores, exclude: c.selectedStoreIds.toSet());
                      if (picked != null) c.addStore(picked);
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add store'),
                  ),
                ]);
              }),
            ),
            const SizedBox(height: Gap.xl),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(onPressed: () => Get.back(), child: const Text('Cancel')),
              const SizedBox(width: Gap.sm),
              Obx(() => FilledButton(
                    onPressed: c.saving.value
                        ? null
                        : () async {
                            final saved = await c.save();
                            if (saved != null) {
                              Toast.success(editing == null ? 'Packing order created' : 'Packing order updated');
                              Get.offNamed(AppRoutes.packingOrder(saved.id));
                            }
                          },
                    child: c.saving.value ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(editing == null ? 'Create draft' : 'Save changes'),
                  )),
            ]),
          ]),
        );
      }),
    );
  }
}

class _AllocationMatrix extends StatelessWidget {
  const _AllocationMatrix({required this.c});
  final PackingFormController c;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 48,
        dataRowMaxHeight: 48,
        columnSpacing: 16,
        columns: [
          const DataColumn(label: Text('Product', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600))),
          for (final storeId in c.selectedStoreIds)
            DataColumn(
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(c.allStores.firstWhere((s) => s.id == storeId).name, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  tooltip: 'Edit this store\'s products',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => showStoreProductsDialog(c, c.allStores.firstWhere((s) => s.id == storeId)),
                ),
                const SizedBox(width: 4),
                IconButton(icon: const Icon(Icons.close, size: 14), tooltip: 'Remove store', padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => c.removeStore(storeId)),
              ]),
            ),
          const DataColumn(label: Text('Remaining', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600))),
        ],
        rows: [
          for (final p in c.products)
            DataRow(cells: [
              DataCell(SizedBox(width: 140, child: Text(p.product.name, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis))),
              for (final storeId in c.selectedStoreIds)
                DataCell(QuantityInput(value: c.allocations[p.product.id]?[storeId] ?? 0, width: 76, onChanged: (v) => c.setAllocation(p.product.id, storeId, v))),
              DataCell(Builder(builder: (context) {
                final remaining = c.remainingFor(p.product.id);
                return Text('$remaining', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: remaining == 0 ? AppColors.success : remaining < 0 ? AppColors.danger : AppColors.warning));
              })),
            ]),
          DataRow(cells: [
            const DataCell(Text('Store total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
            for (final storeId in c.selectedStoreIds)
              DataCell(Builder(builder: (context) {
                final total = c.totalForStore(storeId);
                return Text('$total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: total == 0 ? AppColors.danger : AppColors.textPrimary));
              })),
            const DataCell(SizedBox()),
          ]),
        ],
      ),
    );
  }
}
