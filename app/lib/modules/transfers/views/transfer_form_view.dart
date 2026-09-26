import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/quantity_lines_editor.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/toast.dart';
import '../controllers/transfer_form_controller.dart';

class TransferFormView extends StatelessWidget {
  const TransferFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(TransferFormController(Get.find(), Get.find(), Get.find()));
    return ShellPage(
      title: 'New stock transfer',
      breadcrumb: 'Operations / Transfers',
      child: Obx(() {
        if (c.loading.value) return const LoadingView();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(Gap.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SectionCard(
              title: 'Transfer details',
              child: FormColumn(children: [
                if (c.isStore)
                  Obx(() => Row(children: [
                        const Text('Direction:', style: TextStyle(fontSize: 13, color: Colors.black87)),
                        const SizedBox(width: Gap.md),
                        ChoiceChip(label: const Text('Request stock in'), selected: c.direction.value == 'IN', onSelected: (_) => c.setDirection('IN')),
                        const SizedBox(width: Gap.sm),
                        ChoiceChip(label: const Text('Send stock out'), selected: c.direction.value == 'OUT', onSelected: (_) => c.setDirection('OUT')),
                      ]))
                else
                  Obx(() => Row(children: [
                        const Text('Source:', style: TextStyle(fontSize: 13, color: Colors.black87)),
                        const SizedBox(width: Gap.md),
                        ChoiceChip(label: const Text('Warehouse'), selected: c.sourceType.value == 'WAREHOUSE', onSelected: (_) => c.sourceType.value = 'WAREHOUSE'),
                        const SizedBox(width: Gap.sm),
                        ChoiceChip(label: const Text('Store'), selected: c.sourceType.value == 'STORE', onSelected: (_) => c.sourceType.value = 'STORE'),
                      ])),
                Obx(() {
                  final storeToStore = c.isStore ? c.direction.value == 'OUT' : c.sourceType.value == 'STORE';
                  return FieldRow(children: [
                    if (storeToStore && !(c.isStore && c.direction.value == 'OUT'))
                      AppDropdownField<String>(label: 'From store', required: true, value: c.fromStoreId.value, items: c.stores.map((s) => s.id).toList(), itemLabel: (id) => c.stores.firstWhere((s) => s.id == id).name, onChanged: (v) => c.fromStoreId.value = v),
                    if (!(c.isStore && c.direction.value == 'IN'))
                      AppDropdownField<String>(
                        label: 'To store',
                        required: true,
                        value: c.toStoreId.value,
                        items: c.stores.where((s) => s.id != c.fromStoreId.value).map((s) => s.id).toList(),
                        itemLabel: (id) => c.stores.firstWhere((s) => s.id == id).name,
                        onChanged: (v) => c.toStoreId.value = v,
                      ),
                  ]);
                }),
                TextFormField(decoration: const InputDecoration(labelText: 'Notes (optional)'), maxLines: 2, maxLength: 1000, onChanged: (v) => c.notes.value = v),
                FormSectionTitle('Products'),
                Obx(() {
                  c.lines.length; // subscribe to the RxList so add/remove rebuilds this editor
                  return QuantityLinesEditor(lines: c.lines, onChanged: (_) {}, emptyHint: 'Add the products to transfer.');
                }),
                const SizedBox(height: Gap.sm),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  OutlinedButton(onPressed: () => Get.back(), child: const Text('Cancel')),
                  const SizedBox(width: Gap.sm),
                  Obx(() => FilledButton(
                        onPressed: c.saving.value
                            ? null
                            : () async {
                                final saved = await c.save();
                                if (saved != null) {
                                  Toast.success('Transfer requested');
                                  Get.offNamed(AppRoutes.transfer(saved.id));
                                }
                              },
                        child: c.saving.value ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Request transfer'),
                      )),
                ]),
              ]),
            ),
          ),
        );
      }),
    );
  }
}
