import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/quantity_lines_editor.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/repositories/repositories.dart';

enum StockEntryMode { opening, purchase, adjustment, damage, writeOff }

/// One dialog covers opening stock, purchases, adjustments, damage reports and
/// damage write-offs - the fields shown adapt to [mode]. Returns true if saved.
Future<bool> showStockEntryDialog({
  required StockEntryMode mode,
  required bool isWarehouse,
  String? storeId,
  String? warehouseId,
  List<StoreModel> stores = const [],
  List<Warehouse> warehouses = const [],
}) async {
  final repo = Get.find<StockRepository>();
  final formKey = GlobalKey<FormState>();
  final lines = <QuantityLine>[];
  final reasonController = TextEditingController();
  final refController = TextEditingController();
  final selectedStoreId = RxnString(storeId);
  final selectedWarehouseId = RxnString(warehouseId ?? warehouses.firstWhereOrNull((w) => w.isDefault)?.id);
  final bucket = 'AVAILABLE'.obs;
  final saving = false.obs;
  final linesVersion = 0.obs; // bumps to force rebuild of the Add button state

  final title = switch (mode) {
    StockEntryMode.opening => 'Record opening stock',
    StockEntryMode.purchase => 'Record purchase',
    StockEntryMode.adjustment => 'Stock adjustment',
    StockEntryMode.damage => 'Report damaged stock',
    StockEntryMode.writeOff => 'Write off damaged stock',
  };
  final needsReason = mode == StockEntryMode.adjustment || mode == StockEntryMode.damage || mode == StockEntryMode.writeOff;
  final allowNegative = mode == StockEntryMode.adjustment;
  final showBucket = mode == StockEntryMode.adjustment;

  final result = await Get.dialog<bool>(
    AppDialog(
      title: title,
      width: 620,
      actions: [
        OutlinedButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
        Obx(() => FilledButton(
              onPressed: saving.value
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      if (lines.isEmpty) return Toast.warning('Add at least one product');
                      if (!isWarehouse && selectedStoreId.value == null) return Toast.warning('Select a store');
                      if (lines.any((l) => l.quantity == 0)) return Toast.warning('Quantity cannot be zero');
                      saving.value = true;
                      try {
                        final location = isWarehouse
                            ? {'locationType': 'WAREHOUSE', 'warehouseId': selectedWarehouseId.value}
                            : {'locationType': 'STORE', 'storeId': selectedStoreId.value};
                        switch (mode) {
                          case StockEntryMode.opening:
                            await repo.opening({...location, 'items': lines.map((l) => {'productId': l.product.id, 'quantity': l.quantity, if (l.note?.isNotEmpty == true) 'reason': l.note}).toList()});
                          case StockEntryMode.purchase:
                            await repo.purchase({
                              'warehouseId': selectedWarehouseId.value,
                              if (refController.text.trim().isNotEmpty) 'supplierReference': refController.text.trim(),
                              'items': lines.map((l) => {'productId': l.product.id, 'quantity': l.quantity, if (l.note?.isNotEmpty == true) 'reason': l.note}).toList(),
                            });
                          case StockEntryMode.adjustment:
                            await repo.adjust({...location, 'reason': reasonController.text.trim(), 'bucket': bucket.value, 'items': lines.map((l) => {'productId': l.product.id, 'quantity': l.quantity}).toList()});
                          case StockEntryMode.damage:
                            await repo.reportDamage({...location, 'items': lines.map((l) => {'productId': l.product.id, 'quantity': l.quantity, 'reason': l.note?.isNotEmpty == true ? l.note : reasonController.text.trim()}).toList()});
                          case StockEntryMode.writeOff:
                            await repo.writeOff({...location, 'items': lines.map((l) => {'productId': l.product.id, 'quantity': l.quantity, 'reason': l.note?.isNotEmpty == true ? l.note : reasonController.text.trim()}).toList()});
                        }
                        Get.back(result: true);
                      } catch (e) {
                        Toast.error(AppException.from(e).detailedMessage);
                      } finally {
                        saving.value = false;
                      }
                    },
              child: saving.value ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
            )),
      ],
      child: Form(
        key: formKey,
        child: FormColumn(children: [
          if (isWarehouse)
            Obx(() => AppDropdownField<String>(label: 'Warehouse', value: selectedWarehouseId.value, required: true, items: warehouses.map((w) => w.id).toList(), itemLabel: (id) => warehouses.firstWhere((w) => w.id == id).name, onChanged: (v) => selectedWarehouseId.value = v))
          else if (stores.isNotEmpty)
            Obx(() => AppDropdownField<String>(label: 'Store', value: selectedStoreId.value, required: true, items: stores.map((s) => s.id).toList(), itemLabel: (id) => stores.firstWhere((s) => s.id == id).name, onChanged: (v) => selectedStoreId.value = v)),
          if (mode == StockEntryMode.purchase) AppTextField(label: 'Supplier reference', controller: refController, hint: 'e.g. PO-1042'),
          if (showBucket)
            Obx(() => Row(children: [
                  const Text('Bucket:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(width: Gap.md),
                  ChoiceChip(label: const Text('Available'), selected: bucket.value == 'AVAILABLE', onSelected: (_) => bucket.value = 'AVAILABLE'),
                  const SizedBox(width: Gap.sm),
                  ChoiceChip(label: const Text('Damaged'), selected: bucket.value == 'DAMAGED', onSelected: (_) => bucket.value = 'DAMAGED'),
                ])),
          if (needsReason) AppTextField(label: 'Reason', controller: reasonController, required: mode == StockEntryMode.adjustment, maxLength: 300, validator: mode == StockEntryMode.adjustment ? (v) => (v == null || v.trim().isEmpty) ? 'Reason is required' : null : null),
          FormSectionTitle('Products', subtitle: allowNegative ? 'Enter a negative quantity to reduce stock.' : null),
          Obx(() {
            linesVersion.value;
            return QuantityLinesEditor(
              lines: lines,
              onChanged: (_) => linesVersion.value++,
              allowNegative: allowNegative,
              showNote: mode == StockEntryMode.damage || mode == StockEntryMode.writeOff || mode == StockEntryMode.opening,
              noteLabel: mode == StockEntryMode.opening ? 'Note (optional)' : 'Reason for this product (optional, uses the reason above if blank)',
            );
          }),
        ]),
      ),
    ),
  );
  return result ?? false;
}
