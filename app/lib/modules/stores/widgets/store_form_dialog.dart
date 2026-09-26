import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/repositories.dart';

/// Create/edit store dialog. Returns true if saved.
Future<bool> showStoreFormDialog({StoreModel? store, required List<AppUser> managers}) async {
  final repo = Get.find<StoreRepository>();
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController(text: store?.name);
  final codeController = TextEditingController(text: store?.code);
  final addressController = TextEditingController(text: store?.address);
  final cityController = TextEditingController(text: store?.city);
  final phoneController = TextEditingController(text: store?.phone);
  final emailController = TextEditingController(text: store?.email);
  final contactController = TextEditingController(text: store?.contactPerson);
  final managerId = RxnString(store?.assignedManagerId);
  final saving = false.obs;
  final fieldErrors = <String, String>{}.obs;

  final result = await Get.dialog<bool>(
    AppDialog(
      title: store == null ? 'New store' : 'Edit ${store.name}',
      width: 600,
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
                        'address': addressController.text.trim().isEmpty ? null : addressController.text.trim(),
                        'city': cityController.text.trim().isEmpty ? null : cityController.text.trim(),
                        'phone': phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                        'email': emailController.text.trim().isEmpty ? null : emailController.text.trim(),
                        'contactPerson': contactController.text.trim().isEmpty ? null : contactController.text.trim(),
                        'assignedManagerId': managerId.value,
                      };
                      try {
                        store == null ? await repo.create(body) : await repo.update(store.id, body);
                        Get.back(result: true);
                      } catch (e) {
                        final err = AppException.from(e);
                        fieldErrors.assignAll(err.fieldErrors);
                        if (err.fieldErrors.isEmpty) Get.back(result: false);
                      } finally {
                        saving.value = false;
                      }
                    },
              child: saving.value ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(store == null ? 'Create store' : 'Save changes'),
            )),
      ],
      child: Form(
        key: formKey,
        child: Obx(() => FormColumn(children: [
              FieldRow(children: [
                AppTextField(label: 'Store name', controller: nameController, required: true, maxLength: 120, validator: V.required('Store name'), serverError: fieldErrors['name']),
                AppTextField(label: 'Store code', controller: codeController, required: true, maxLength: 30, validator: V.all([V.required('Store code'), V.code]), serverError: fieldErrors['code']),
              ]),
              AppTextField(label: 'Address', controller: addressController, maxLines: 2, maxLength: 300),
              FieldRow(children: [
                AppTextField(label: 'City', controller: cityController, maxLength: 80),
                AppTextField(label: 'Phone', controller: phoneController, maxLength: 20, validator: V.phone),
              ]),
              FieldRow(children: [
                AppTextField(label: 'Email', controller: emailController, validator: V.email, serverError: fieldErrors['email']),
                AppTextField(label: 'Contact person', controller: contactController, maxLength: 100),
              ]),
              AppDropdownField<String?>(
                label: 'Assigned manager',
                value: managerId.value,
                items: [null, ...managers.map((m) => m.id)],
                itemLabel: (id) => id == null ? 'Unassigned' : managers.firstWhere((m) => m.id == id).name,
                onChanged: (v) => managerId.value = v,
                serverError: fieldErrors['assignedManagerId'],
              ),
            ])),
      ),
    ),
  );
  return result ?? false;
}
