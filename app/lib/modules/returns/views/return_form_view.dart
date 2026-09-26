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
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/sales.dart';
import '../controllers/return_form_controller.dart';

class ReturnFormView extends StatelessWidget {
  const ReturnFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final sale = Get.arguments as Sale?;
    final c = Get.put(ReturnFormController(Get.find(), Get.find(), sourceSale: sale));
    return ShellPage(
      title: 'New return',
      breadcrumb: sale == null ? 'Sales' : 'Sales / ${sale.invoiceNumber}',
      child: Obx(() {
        if (c.loading.value) return const LoadingView();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(Gap.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!c.fromSale && !c.isStore)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.lg),
                  child: SectionCard(
                    title: 'Store',
                    child: Obx(() => AppDropdownField<String>(label: 'Store', required: true, value: c.storeId.value, items: c.stores.map((s) => s.id).toList(), itemLabel: (id) => c.stores.firstWhere((s) => s.id == id).name, onChanged: (v) => c.storeId.value = v)),
                  ),
                ),
              if (c.fromSale)
                SectionCard(
                  title: 'Select items to return',
                  subtitle: 'Only items with returnable quantity from ${sale!.invoiceNumber} are shown.',
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (final item in c.returnableSaleItems) ...[
                      Obx(() {
                        final selected = c.lines.any((l) => l.product.id == item.product.id);
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (v) => c.toggleSaleItem(item, v ?? false),
                          title: Text(item.product.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          subtitle: Text('Sold ${item.quantity} · Returnable ${item.returnableQuantity}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                          dense: true,
                        );
                      }),
                      const Divider(height: 1),
                    ],
                  ]),
                )
              else
                SectionCard(
                  title: 'Products',
                  actions: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await pickProductDialog(exclude: c.lines.map((l) => l.product.id).toSet());
                        if (picked != null) c.addLine(picked);
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add product'),
                    ),
                  ],
                  child: Obx(() => c.lines.isEmpty ? const Text('No products added yet.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)) : const SizedBox()),
                ),
              const SizedBox(height: Gap.lg),
              SectionCard(
                title: 'Return details',
                child: Obx(() => Column(children: [
                      for (var i = 0; i < c.lines.length; i++) _ReturnLineEditor(controller: c, index: i),
                      if (c.lines.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: Gap.lg), child: Text('Select items above to continue.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted))),
                    ])),
              ),
              const SizedBox(height: Gap.xl),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton(onPressed: () => Get.back(), child: const Text('Cancel')),
                const SizedBox(width: Gap.sm),
                Obx(() => FilledButton(
                      onPressed: c.saving.value
                          ? null
                          : () async {
                              final result = await c.submit();
                              if (result != null) {
                                Toast.success('Return recorded');
                                Get.offNamed(AppRoutes.saleReturn(result.id));
                              }
                            },
                      child: c.saving.value ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Record return'),
                    )),
              ]),
            ]),
          ),
        );
      }),
    );
  }
}

class _ReturnLineEditor extends StatelessWidget {
  const _ReturnLineEditor({required this.controller, required this.index});
  final ReturnFormController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final line = controller.lines[index];
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.md),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(Radii.md)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(line.product.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          if (!controller.fromSale) IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => controller.removeLine(index)),
        ]),
        const SizedBox(height: Gap.sm),
        Row(children: [
          Text('Quantity', style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          QuantityInput(value: line.quantity, max: line.maxQuantity, onChanged: (v) {
            line.quantity = v;
            controller.lines.refresh();
          }),
        ]),
        const SizedBox(height: Gap.sm),
        Row(children: [
          const Text('Condition:', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          const SizedBox(width: Gap.md),
          ChoiceChip(
            label: const Text('Good'),
            selected: line.condition == 'GOOD',
            onSelected: (_) {
              line.condition = 'GOOD';
              controller.lines.refresh();
            },
          ),
          const SizedBox(width: Gap.sm),
          ChoiceChip(
            label: const Text('Damaged'),
            selected: line.condition == 'DAMAGED',
            selectedColor: Tone.danger.bg,
            onSelected: (_) {
              line.condition = 'DAMAGED';
              controller.lines.refresh();
            },
          ),
        ]),
        const SizedBox(height: Gap.sm),
        TextFormField(
          initialValue: line.reason,
          decoration: const InputDecoration(labelText: 'Reason *', isDense: true),
          maxLength: 300,
          onChanged: (v) {
            line.reason = v;
            controller.lines.refresh();
          },
        ),
      ]),
    );
  }
}
