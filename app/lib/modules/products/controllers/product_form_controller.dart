import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/repositories/repositories.dart';

/// Backs the create/edit product dialog. Pass an existing [product] to edit.
class ProductFormController extends GetxController {
  ProductFormController(this._repo, {this.product});

  final ProductRepository _repo;
  final Product? product;
  bool get isEdit => product != null;

  final formKey = GlobalKey<FormState>();
  late final nameController = TextEditingController(text: product?.name);
  late final skuController = TextEditingController(text: product?.sku);
  late final barcodeController = TextEditingController(text: product?.barcode);
  late final brandController = TextEditingController(text: product?.brand);
  late final unitController = TextEditingController(text: product?.unit ?? 'PCS');
  late final descriptionController = TextEditingController(text: product?.description);
  late final purchasePriceController = TextEditingController(text: product?.purchasePrice?.toStringAsFixed(2));
  late final sellingPriceController = TextEditingController(text: product?.sellingPrice.toStringAsFixed(2));
  late final taxRateController = TextEditingController(text: (product?.taxRate ?? 0).toStringAsFixed(0));
  late final minStockController = TextEditingController(text: '${product?.minimumStock ?? 0}');
  late final maxStockController = TextEditingController(text: product?.maximumStock?.toString());
  late final imageUrlController = TextEditingController(text: product?.imageUrl);

  final categoryId = RxnString();
  final saving = false.obs;
  final fieldErrors = <String, String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    categoryId.value = product?.categoryId;
  }

  @override
  void onClose() {
    for (final c in [nameController, skuController, barcodeController, brandController, unitController, descriptionController, purchasePriceController, sellingPriceController, taxRateController, minStockController, maxStockController, imageUrlController]) {
      c.dispose();
    }
    super.onClose();
  }

  Map<String, dynamic> _body() => {
        'name': nameController.text.trim(),
        'sku': skuController.text.trim(),
        'barcode': barcodeController.text.trim().isEmpty ? null : barcodeController.text.trim(),
        'categoryId': categoryId.value,
        'brand': brandController.text.trim().isEmpty ? null : brandController.text.trim(),
        'unit': unitController.text.trim().isEmpty ? 'PCS' : unitController.text.trim(),
        'description': descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
        'purchasePrice': double.tryParse(purchasePriceController.text.trim()) ?? 0,
        'sellingPrice': double.tryParse(sellingPriceController.text.trim()) ?? 0,
        'taxRate': double.tryParse(taxRateController.text.trim()) ?? 0,
        'minimumStock': int.tryParse(minStockController.text.trim()) ?? 0,
        'maximumStock': maxStockController.text.trim().isEmpty ? null : int.tryParse(maxStockController.text.trim()),
        'imageUrl': imageUrlController.text.trim().isEmpty ? null : imageUrlController.text.trim(),
      };

  /// Returns the saved product on success, null on failure (errors surfaced inline).
  Future<Product?> submit() async {
    fieldErrors.clear();
    if (categoryId.value == null) {
      fieldErrors['categoryId'] = 'Category is required';
    }
    if (!formKey.currentState!.validate() || categoryId.value == null) {
      formKey.currentState!.validate();
      return null;
    }
    saving.value = true;
    try {
      final result = isEdit ? await _repo.update(product!.id, _body()) : await _repo.create(_body());
      return result;
    } catch (e) {
      final err = AppException.from(e);
      fieldErrors.assignAll(err.fieldErrors);
      if (err.fieldErrors.isEmpty) Toast.error(err.message);
      return null;
    } finally {
      saving.value = false;
    }
  }
}
