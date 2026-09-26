import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../data/models/catalog.dart';
import '../../../data/repositories/repositories.dart';

/// Create/edit category dialog. Returns true if saved.
Future<bool> showCategoryFormDialog({Category? category, required List<Category> allCategories}) async {
  final repo = Get.find<CategoryRepository>();
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController(text: category?.name);
  final codeController = TextEditingController(text: category?.code);
  final descController = TextEditingController(text: category?.description);
  final parentId = RxnString(category?.parentId);
  final saving = false.obs;
  final fieldErrors = <String, String>{}.obs;

  // A category cannot become its own parent (self, or - conservatively - itself only;
  // deeper cycle checks are enforced by the server).
  final parentOptions = allCategories.where((c) => c.id != category?.id).toList();

  final result = await Get.dialog<bool>(
    AppDialog(
      title: category == null ? 'New category' : 'Edit ${category.name}',
      width: 520,
      actions: [
        OutlinedButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
        Obx(() => FilledButton(
              onPressed: saving.value
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      saving.value = true;
                      fieldErrors.clear();
                      final body = {
                        'name': nameController.text.trim(),
                        'code': codeController.text.trim(),
                        'description': descController.text.trim().isEmpty ? null : descController.text.trim(),
                        'parentId': parentId.value,
                      };
                      try {
                        category == null ? await repo.create(body) : await repo.update(category.id, body);
                        Get.back(result: true);
                      } catch (e) {
                        final err = AppException.from(e);
                        fieldErrors.assignAll(err.fieldErrors);
                        if (err.fieldErrors.isEmpty) Get.back(result: false);
                      } finally {
                        saving.value = false;
                      }
                    },
              child: saving.value ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(category == null ? 'Create' : 'Save changes'),
            )),
      ],
      child: Form(
        key: formKey,
        child: Obx(() => FormColumn(children: [
              FieldRow(children: [
                AppTextField(label: 'Category name', controller: nameController, required: true, maxLength: 100, validator: V.required('Category name'), serverError: fieldErrors['name']),
                AppTextField(label: 'Code', controller: codeController, required: true, maxLength: 30, validator: V.all([V.required('Code'), V.code]), serverError: fieldErrors['code']),
              ]),
              AppDropdownField<String?>(
                label: 'Parent category',
                value: parentId.value,
                items: [null, ...parentOptions.map((c) => c.id)],
                itemLabel: (id) => id == null ? 'None (top-level)' : parentOptions.firstWhere((c) => c.id == id).displayName,
                onChanged: (v) => parentId.value = v,
                serverError: fieldErrors['parentId'],
              ),
              AppTextField(label: 'Description', controller: descController, maxLines: 3, maxLength: 500),
            ])),
      ),
    ),
  );

  return result ?? false;
}
