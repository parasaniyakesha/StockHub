import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/repositories.dart';

/// Create/edit a store user. Returns true if saved. Managers may only create
/// store users for their own stores (enforced server-side too).
Future<bool> showUserFormDialog({AppUser? user, required List<StoreModel> stores, bool managerOnlyStoreUsers = false}) async {
  final repo = Get.find<UserRepository>();
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController(text: user?.name);
  final emailController = TextEditingController(text: user?.email);
  final phoneController = TextEditingController(text: user?.phone);
  final passwordController = TextEditingController();
  final role = (user?.role ?? (managerOnlyStoreUsers ? 'STORE' : 'STORE')).obs;
  final storeId = RxnString(user?.storeId);
  final saving = false.obs;
  final fieldErrors = <String, String>{}.obs;
  final isEdit = user != null;

  final result = await Get.dialog<bool>(
    AppDialog(
      title: isEdit ? 'Edit ${user.name}' : 'New user',
      width: 560,
      actions: [
        OutlinedButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
        Obx(() => FilledButton(
              onPressed: saving.value
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      saving.value = true;
                      fieldErrors.clear();
                      try {
                        if (isEdit) {
                          await repo.update(user.id, {'name': nameController.text.trim(), 'phone': phoneController.text.trim().isEmpty ? null : phoneController.text.trim(), if (role.value == 'STORE') 'storeId': storeId.value});
                        } else {
                          await repo.create({
                            'name': nameController.text.trim(),
                            'email': emailController.text.trim(),
                            'phone': phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                            'password': passwordController.text,
                            'role': role.value,
                            if (role.value == 'STORE') 'storeId': storeId.value,
                          });
                        }
                        Get.back(result: true);
                      } catch (e) {
                        final err = AppException.from(e);
                        fieldErrors.assignAll(err.fieldErrors);
                        if (err.fieldErrors.isEmpty) Get.back(result: false);
                      } finally {
                        saving.value = false;
                      }
                    },
              child: saving.value ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(isEdit ? 'Save changes' : 'Create user'),
            )),
      ],
      child: Form(
        key: formKey,
        child: Obx(() => FormColumn(children: [
              if (!isEdit && !managerOnlyStoreUsers)
                AppDropdownField<String>(label: 'Role', required: true, value: role.value, items: const ['ADMIN', 'MANAGER', 'STORE'], itemLabel: (r) => switch (r) { 'ADMIN' => 'Administrator', 'MANAGER' => 'Manager', _ => 'Store user' }, onChanged: (v) => role.value = v ?? 'STORE'),
              FieldRow(children: [
                AppTextField(label: 'Full name', controller: nameController, required: true, maxLength: 100, validator: V.required('Name'), serverError: fieldErrors['name']),
                AppTextField(label: 'Email', controller: emailController, required: true, enabled: !isEdit, validator: V.all([V.required('Email'), V.email]), serverError: fieldErrors['email']),
              ]),
              AppTextField(label: 'Phone', controller: phoneController, maxLength: 20, validator: V.phone),
              if (!isEdit) AppTextField(label: 'Temporary password', controller: passwordController, required: true, obscure: true, validator: V.password, serverError: fieldErrors['password']),
              if (role.value == 'STORE')
                AppDropdownField<String>(label: 'Store', required: true, value: storeId.value, items: stores.map((s) => s.id).toList(), itemLabel: (id) => stores.firstWhere((s) => s.id == id).name, onChanged: (v) => storeId.value = v, serverError: fieldErrors['storeId']),
            ])),
      ),
    ),
  );
  return result ?? false;
}
