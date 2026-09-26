import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/product_picker.dart';
import '../../../data/models/catalog.dart';
import '../controllers/packing_form_controller.dart';

/// "Store → its products": build up one store's product list and quantities
/// in a single step, instead of filling the whole product/store matrix.
Future<void> showStoreProductsDialog(PackingFormController c, StoreModel store) async {
  // Seed with whatever this store already has allocated in the order.
  final lines = <ProductBrief, int>{
    for (final p in c.products)
      if ((c.allocations[p.product.id]?[store.id] ?? 0) > 0) p.product: c.allocations[p.product.id]![store.id]!,
  };
  final version = 0.obs;

  await Get.dialog<void>(
    AppDialog(
      title: 'Products for ${store.name}',
      subtitle: 'Build this store\'s share of the order directly.',
      width: 520,
      actions: [
        OutlinedButton(onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            c.applyStoreLines(store, Map.of(lines));
            Get.back();
          },
          child: const Text('Apply'),
        ),
      ],
      child: Obx(() {
        version.value;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (lines.isEmpty)
            Container(
              padding: const EdgeInsets.all(Gap.lg),
              decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(Radii.md)),
              child: const Center(child: Text('Add the products this store should receive.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted))),
            )
          else
            Container(
              decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(Radii.md)),
              child: Column(children: [
                for (final (i, entry) in lines.entries.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(entry.key.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(entry.key.sku, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ]),
                      ),
                      QuantityInput(
                        value: entry.value,
                        onChanged: (v) {
                          lines[entry.key] = v;
                          version.value++;
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          lines.remove(entry.key);
                          version.value++;
                        },
                      ),
                    ]),
                  ),
                ],
              ]),
            ),
          const SizedBox(height: Gap.sm),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await pickProductDialog(exclude: lines.keys.map((p) => p.id).toSet());
              if (picked != null) {
                lines[picked] = 1;
                version.value++;
              }
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add product'),
          ),
        ]);
      }),
    ),
  );
}
