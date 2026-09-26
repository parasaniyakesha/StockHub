import 'package:get/get.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/session/settings_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/sales.dart';
import '../../../data/repositories/repositories.dart';

class SaleLine {
  SaleLine({required this.product, this.quantity = 1, double? unitPrice, this.discount = 0}) : unitPrice = unitPrice ?? (product.sellingPrice ?? 0);
  final ProductBrief product;
  int quantity;
  double unitPrice;
  double discount;

  double get gross => unitPrice * quantity;
  double get taxable => (gross - discount).clamp(0, double.infinity);
  double get tax => taxable * product.taxRate / 100;
  double get total => taxable + tax;
}

class SaleFormController extends GetxController {
  SaleFormController(this._repo, this._storeRepo);
  final SaleRepository _repo;
  final StoreRepository _storeRepo;

  final loading = true.obs;
  final saving = false.obs;
  final storeId = RxnString();
  final stores = <StoreModel>[].obs;
  final customerName = ''.obs;
  final customerPhone = ''.obs;
  final paymentMethod = 'CASH'.obs;
  final discount = 0.0.obs;
  final notes = ''.obs;
  final lines = <SaleLine>[].obs;
  final _clientRequestId = newClientRequestId();

  bool get isStore => Get.find<AuthService>().isStore;
  bool get allowPriceOverride => Get.find<SettingsService>().settings.value.allowPriceOverride || !isStore;

  double get subtotal => lines.fold(0.0, (a, l) => a + l.taxable);
  double get tax => lines.fold(0.0, (a, l) => a + l.tax);
  double get grandTotal => (subtotal + tax - discount.value).clamp(0, double.infinity);

  @override
  void onInit() {
    super.onInit();
    _init();
  }

  Future<void> _init() async {
    if (!isStore) {
      try {
        stores.assignAll(await _storeRepo.all());
      } catch (_) {}
    }
    loading.value = false;
  }

  void addLine(ProductBrief p) {
    if (lines.any((l) => l.product.id == p.id)) return;
    lines.add(SaleLine(product: p));
  }

  void removeLine(int index) => lines.removeAt(index);

  Future<Sale?> submit() async {
    if (lines.isEmpty) {
      Toast.warning('Add at least one product');
      return null;
    }
    if (!isStore && storeId.value == null) {
      Toast.warning('Select a store');
      return null;
    }
    if (lines.any((l) => l.quantity <= 0)) {
      Toast.warning('Quantity must be greater than 0 for every product');
      return null;
    }
    saving.value = true;
    try {
      final result = await _repo.create({
        if (!isStore) 'storeId': storeId.value,
        if (customerName.value.trim().isNotEmpty) 'customerName': customerName.value.trim(),
        if (customerPhone.value.trim().isNotEmpty) 'customerPhone': customerPhone.value.trim(),
        'paymentMethod': paymentMethod.value,
        'discount': discount.value,
        if (notes.value.trim().isNotEmpty) 'notes': notes.value.trim(),
        'clientRequestId': _clientRequestId,
        'items': lines.map((l) => {'productId': l.product.id, 'quantity': l.quantity, 'unitPrice': l.unitPrice, 'discount': l.discount}).toList(),
      });
      return result;
    } catch (e) {
      Toast.error(AppException.from(e).detailedMessage);
      return null;
    } finally {
      saving.value = false;
    }
  }
}
