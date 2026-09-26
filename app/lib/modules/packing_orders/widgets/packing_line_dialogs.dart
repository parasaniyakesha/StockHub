import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../data/models/operations.dart';

/// Pack dialog: one row per store-product allocation, default = allocated qty.
/// Returns lineId -> packedQuantity, or null if cancelled.
Future<Map<String, int>?> showPackDialog(PackingOrder order) async {
  final values = <String, int>{};
  for (final store in order.stores) {
    for (final line in store.lines) {
      if (line.allocatedQuantity > 0) values[line.id] = line.allocatedQuantity;
    }
  }
  final version = 0.obs;

  final result = await Get.dialog<bool>(
    AppDialog(
      title: 'Record packed quantities',
      subtitle: 'Defaults to the full allocated quantity for each line.',
      width: 620,
      actions: [
        OutlinedButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Get.back(result: true), child: const Text('Confirm packing')),
      ],
      child: Obx(() {
        version.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final store in order.stores.where((s) => s.lines.any((l) => l.allocatedQuantity > 0))) ...[
              Padding(padding: const EdgeInsets.only(top: Gap.md, bottom: 4), child: Text(store.store.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
              Container(
                decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(Radii.md)),
                child: Column(children: [
                  for (var i = 0; i < store.lines.length; i++)
                    if (store.lines[i].allocatedQuantity > 0) ...[
                      if (i > 0) const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
                        child: Row(children: [
                          Expanded(child: Text(store.lines[i].product.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                          Text('of ${store.lines[i].allocatedQuantity}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                          const SizedBox(width: Gap.sm),
                          QuantityInput(value: values[store.lines[i].id] ?? 0, max: store.lines[i].allocatedQuantity, onChanged: (v) {
                            values[store.lines[i].id] = v;
                            version.value++;
                          }),
                        ]),
                      ),
                    ],
                ]),
              ),
            ],
          ],
        );
      }),
    ),
  );
  return result == true ? values : null;
}

/// Receive dialog for one store section: received/damaged per line, default
/// received = dispatched, damaged = 0. Returns the lines payload, or null if cancelled.
Future<List<Map<String, dynamic>>?> showReceiveDialog(PackingStore section) async {
  final received = <String, int>{};
  final damaged = <String, int>{};
  for (final line in section.lines) {
    if (line.dispatchedQuantity > 0) {
      received[line.id] = line.dispatchedQuantity;
      damaged[line.id] = 0;
    }
  }
  final version = 0.obs;

  final result = await Get.dialog<bool>(
    AppDialog(
      title: 'Receive shipment',
      subtitle: '${section.store.name} - confirm what arrived in good condition and what was damaged.',
      width: 620,
      actions: [
        OutlinedButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Get.back(result: true), child: const Text('Confirm receipt')),
      ],
      child: Obx(() {
        version.value;
        return Container(
          decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(Radii.md)),
          child: Column(children: [
            Container(
              color: AppColors.surfaceMuted,
              padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 8),
              child: const Row(children: [
                Expanded(child: Text('Product', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                SizedBox(width: 60, child: Text('Sent', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                SizedBox(width: 12),
                SizedBox(width: 88, child: Text('Received', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                SizedBox(width: 12),
                SizedBox(width: 88, child: Text('Damaged', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              ]),
            ),
            for (var i = 0; i < section.lines.length; i++)
              if (section.lines[i].dispatchedQuantity > 0) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
                  child: Row(children: [
                    Expanded(child: Text(section.lines[i].product.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                    SizedBox(width: 60, child: Text('${section.lines[i].dispatchedQuantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted))),
                    const SizedBox(width: 12),
                    QuantityInput(value: received[section.lines[i].id] ?? 0, width: 88, onChanged: (v) {
                      received[section.lines[i].id] = v;
                      version.value++;
                    }),
                    const SizedBox(width: 12),
                    QuantityInput(value: damaged[section.lines[i].id] ?? 0, width: 88, onChanged: (v) {
                      damaged[section.lines[i].id] = v;
                      version.value++;
                    }),
                  ]),
                ),
              ],
          ]),
        );
      }),
    ),
  );
  if (result != true) return null;
  return received.entries.map((e) => {'id': e.key, 'receivedQuantity': e.value, 'damagedQuantity': damaged[e.key] ?? 0}).toList();
}
