import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../data/models/catalog.dart';
import '../../../data/repositories/repositories.dart';
import '../controllers/product_form_controller.dart';

/// Opens the create/edit product dialog. Returns the saved product, or null if cancelled.
Future<Product?> showProductFormDialog({Product? product, required List<Category> categories}) {
  final c = Get.put(ProductFormController(Get.find<ProductRepository>(), product: product), tag: UniqueKey().toString());
  return Get.dialog<Product?>(
    AppDialog(
      title: product == null ? 'New product' : 'Edit ${product.name}',
      width: 640,
      actions: [
        OutlinedButton(onPressed: () => Get.back(result: null), child: const Text('Cancel')),
        Obx(() => FilledButton(
              onPressed: c.saving.value
                  ? null
                  : () async {
                      final saved = await c.submit();
                      if (saved != null) Get.back(result: saved);
                    },
              child: c.saving.value ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(product == null ? 'Create product' : 'Save changes'),
            )),
      ],
      child: Form(
        key: c.formKey,
        child: FormColumn(children: [
          FieldRow(children: [
            AppTextField(label: 'Product name', controller: c.nameController, required: true, maxLength: 150, validator: V.required('Product name')),
            AppTextField(label: 'SKU', controller: c.skuController, required: true, maxLength: 30, validator: V.all([V.required('SKU'), V.code])),
          ]),
          FieldRow(children: [
            AppTextField(label: 'Barcode', controller: c.barcodeController, maxLength: 64),
            Obx(() => AppDropdownField<String>(
                  label: 'Category',
                  required: true,
                  value: c.categoryId.value,
                  items: categories.map((cat) => cat.id).toList(),
                  itemLabel: (id) => categories.firstWhere((cat) => cat.id == id).displayName,
                  onChanged: (v) => c.categoryId.value = v,
                  serverError: c.fieldErrors['categoryId'],
                )),
          ]),
          FieldRow(children: [
            AppTextField(label: 'Brand', controller: c.brandController, maxLength: 80),
            AppTextField(label: 'Unit', controller: c.unitController, maxLength: 20, hint: 'PCS, KG, BOX…'),
          ]),
          AppTextField(label: 'Description', controller: c.descriptionController, maxLines: 3, maxLength: 2000),
          FieldRow(children: [
            AppTextField(label: 'Purchase price', controller: c.purchasePriceController, keyboardType: TextInputType.number, inputFormatters: Formatters.decimal, validator: V.decimal(label: 'Purchase price')),
            AppTextField(label: 'Selling price', controller: c.sellingPriceController, required: true, keyboardType: TextInputType.number, inputFormatters: Formatters.decimal, validator: V.all([V.required('Selling price'), V.decimal(label: 'Selling price')])),
            AppTextField(label: 'Tax rate %', controller: c.taxRateController, keyboardType: TextInputType.number, inputFormatters: Formatters.decimal, validator: V.decimal(label: 'Tax rate', max: 100)),
          ]),
          FieldRow(children: [
            AppTextField(label: 'Minimum stock', controller: c.minStockController, keyboardType: TextInputType.number, inputFormatters: Formatters.digits, validator: V.integer(label: 'Minimum stock', min: 0)),
            AppTextField(label: 'Maximum stock', controller: c.maxStockController, keyboardType: TextInputType.number, inputFormatters: Formatters.digits, validator: V.integer(label: 'Maximum stock', min: 0)),
          ]),
          AppTextField(label: 'Image URL', controller: c.imageUrlController, validator: V.url, hint: 'https://…'),
        ]),
      ),
    ),
  );
}
