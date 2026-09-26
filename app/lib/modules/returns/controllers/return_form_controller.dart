import 'package:get/get.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/sales.dart';
import '../../../data/repositories/repositories.dart';

class ReturnLine {
  ReturnLine({required this.product, this.quantity = 1, this.condition = 'GOOD', this.reason = '', this.maxQuantity});
  final ProductBrief product;
  int quantity;
  String condition;
  String reason;
  final int? maxQuantity;
}

class ReturnFormController extends GetxController {
  ReturnFormController(this._repo, this._storeRepo, {this.sourceSale});
  final SaleRepository _repo;
  final StoreRepository _storeRepo;

  /// If opened from a sale detail page, returns are linked to it and product
  /// choices are limited to that invoice's still-returnable items.
  final Sale? sourceSale;
  bool get fromSale => sourceSale != null;

  final loading = true.obs;
  final saving = false.obs;
  final storeId = RxnString();
  final stores = <StoreModel>[].obs;
  final notes = ''.obs;
  final lines = <ReturnLine>[].obs;
  final _clientRequestId = newClientRequestId();

  bool get isStore => Get.find<AuthService>().isStore;

  @override
  void onInit() {
    super.onInit();
    _init();
  }

  Future<void> _init() async {
    if (sourceSale != null) {
      storeId.value = sourceSale!.store.id;
    } else if (!isStore) {
      try {
        stores.assignAll(await _storeRepo.all());
      } catch (_) {}
    }
    loading.value = false;
  }

  List<SaleItem> get returnableSaleItems => sourceSale?.items.where((i) => i.returnableQuantity > 0).toList() ?? const [];

  void toggleSaleItem(SaleItem item, bool selected) {
    if (selected) {
      if (lines.any((l) => l.product.id == item.product.id)) return;
      lines.add(ReturnLine(product: item.product, quantity: item.returnableQuantity, maxQuantity: item.returnableQuantity));
    } else {
      lines.removeWhere((l) => l.product.id == item.product.id);
    }
  }

  void addLine(ProductBrief p) {
    if (lines.any((l) => l.product.id == p.id)) return;
    lines.add(ReturnLine(product: p));
  }

  void removeLine(int index) => lines.removeAt(index);

  Future<SaleReturn?> submit() async {
    if (lines.isEmpty) {
      Toast.warning('Add at least one product');
      return null;
    }
    if (storeId.value == null) {
      Toast.warning('Select a store');
      return null;
    }
    if (lines.any((l) => l.reason.trim().isEmpty)) {
      Toast.warning('Enter a reason for every product');
      return null;
    }
    saving.value = true;
    try {
      return await _repo.createReturn({
        if (!isStore || fromSale) 'storeId': storeId.value,
        if (sourceSale != null) 'saleId': sourceSale!.id,
        if (notes.value.trim().isNotEmpty) 'notes': notes.value.trim(),
        'clientRequestId': _clientRequestId,
        'items': lines.map((l) => {'productId': l.product.id, 'quantity': l.quantity, 'condition': l.condition, 'reason': l.reason.trim()}).toList(),
      });
    } catch (e) {
      Toast.error(AppException.from(e).detailedMessage);
      return null;
    } finally {
      saving.value = false;
    }
  }
}
