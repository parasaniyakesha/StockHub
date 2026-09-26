import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../controllers/packing_form_controller.dart';

/// "Product → multiple stores": one product, a quantity box per store, all
/// distributed in a single step. Matches the spec's assignment screen -
/// Product A · Available 500 · Store A 100 · Store B 150 · ... · Remaining.
Future<void> showAllocateProductDialog(PackingFormController c, PlannedProduct product) async {
  final quantities = <String, int>{for (final id in c.allStores.map((s) => s.id)) id: c.allocations[product.product.id]?[id] ?? 0};
  final available = 0.obs;
  final loadingAvailable = true.obs;
  final version = 0.obs;

  c.warehouseAvailable(product.product.id).then((v) {
    available.value = v;
    loadingAvailable.value = false;
  });

  await Get.dialog<void>(
    AppDialog(
      title: 'Allocate ${product.product.name}',
      subtitle: '${product.product.sku} · Planned quantity: ${product.quantity}',
      width: 480,
      actions: [
        OutlinedButton(onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            c.applyProductAllocation(product.product.id, Map.of(quantities));
            Get.back();
          },
          child: const Text('Apply'),
        ),
      ],
      child: Obx(() {
        version.value;
        final total = quantities.values.fold(0, (a, b) => a + b);
        final remainingVsPlanned = product.quantity - total;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Obx(() => loadingAvailable.value
              ? const Padding(padding: EdgeInsets.symmetric(vertical: Gap.sm), child: LinearProgressIndicator())
              : InfoBanner(
                  message: 'Available in warehouse: ${available.value} · Allocated so far: $total · Remaining vs planned: $remainingVsPlanned',
                  tone: total > available.value ? Tone.danger : (remainingVsPlanned == 0 ? Tone.success : Tone.warning),
                  icon: Icons.info_outline,
                )),
          const SizedBox(height: Gap.md),
          if (c.allStores.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: Gap.lg), child: EmptyView(compact: true, icon: Icons.storefront_outlined, title: 'No stores available'))
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 360),
              decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(Radii.md)),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: c.allStores.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final store = c.allStores[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
                    child: Row(children: [
                      Expanded(child: Text(store.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                      QuantityInput(
                        value: quantities[store.id] ?? 0,
                        onChanged: (v) {
                          quantities[store.id] = v;
                          version.value++;
                        },
                      ),
                    ]),
                  );
                },
              ),
            ),
        ]);
      }),
    ),
  );
}
