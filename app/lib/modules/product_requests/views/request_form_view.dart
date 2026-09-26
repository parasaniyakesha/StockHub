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
import '../../../data/models/operations.dart';
import '../controllers/request_form_controller.dart';

/// Handles both create (/product-requests/new) and edit (/product-requests/:id/edit).
class RequestFormView extends StatelessWidget {
  const RequestFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final editing = Get.arguments as ProductRequest?;
    final c = Get.put(RequestFormController(Get.find(), Get.find(), editing: editing));
    return ShellPage(
      title: editing == null ? 'New product request' : 'Edit request ${editing.requestNumber}',
      breadcrumb: 'Operations / Requests',
      child: Obx(() {
        if (c.loading.value) return const LoadingView();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(Gap.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SectionCard(
              title: 'Request details',
              subtitle: 'List the products and quantities you need from the central warehouse.',
              child: FormColumn(children: [
                if (!c.isStore)
                  Obx(() => AppDropdownField<String>(
                        label: 'Store',
                        required: true,
                        value: c.storeId.value,
                        items: c.stores.map((s) => s.id).toList(),
                        itemLabel: (id) => c.stores.firstWhere((s) => s.id == id).name,
                        onChanged: (v) => c.storeId.value = v,
                      )),
                TextFormField(
                  initialValue: c.notes.value,
                  maxLines: 3,
                  maxLength: 1000,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  onChanged: (v) => c.notes.value = v,
                ),
                FormSectionTitle('Products'),
                Obx(() {
                  c.lines.length; // subscribe to the RxList so add/remove rebuilds this editor
                  return QuantityLinesEditor(lines: c.lines, onChanged: (_) {}, emptyHint: 'Add products you want to request.');
                }),
                const SizedBox(height: Gap.sm),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  OutlinedButton(onPressed: () => Get.back(), child: const Text('Cancel')),
                  const SizedBox(width: Gap.sm),
                  Obx(() => OutlinedButton(
                        onPressed: c.saving.value
                            ? null
                            : () async {
                                final r = await c.save(submit: false);
                                if (r != null) {
                                  Toast.success('Saved as draft');
                                  Get.offNamed(AppRoutes.request(r.id));
                                }
                              },
                        child: const Text('Save as draft'),
                      )),
                  const SizedBox(width: Gap.sm),
                  Obx(() => FilledButton(
                        onPressed: c.saving.value
                            ? null
                            : () async {
                                final r = await c.save(submit: true);
                                if (r != null) {
                                  Toast.success('Request submitted');
                                  Get.offNamed(AppRoutes.request(r.id));
                                }
                              },
                        child: c.saving.value ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Submit request'),
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
