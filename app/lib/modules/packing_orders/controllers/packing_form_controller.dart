import 'package:get/get.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/operations.dart';
import '../../../data/repositories/repositories.dart';

class PlannedProduct {
  PlannedProduct({required this.product, this.quantity = 0});
  final ProductBrief product;
  int quantity;
}

/// Builds/edits a draft packing order: planned products x planned quantity,
/// selected stores, and a per-product-per-store allocation matrix.
class PackingFormController extends GetxController {
  PackingFormController(this._repo, this._storeRepo, this._productRepo, {this.editing});
  final PackingRepository _repo;
  final StoreRepository _storeRepo;
  final ProductRepository _productRepo;
  final PackingOrder? editing;
  bool get isEdit => editing != null;

  final loading = true.obs;
  final saving = false.obs;
  final notes = ''.obs;
  final warehouseId = RxnString();
  final warehouses = <Warehouse>[].obs;
  final allStores = <StoreModel>[].obs;

  final products = <PlannedProduct>[].obs;
  final selectedStoreIds = <String>[].obs;

  /// productId -> storeId -> allocated qty
  final allocations = <String, Map<String, int>>{}.obs;

  /// Bumped on any allocation edit to force dependent Obx widgets to rebuild.
  final version = 0.obs;

  @override
  void onInit() {
    super.onInit();
    _init();
  }

  Future<void> _init() async {
    try {
      warehouses.assignAll(await _productRepo.warehouses());
      allStores.assignAll(await _storeRepo.all());
      warehouseId.value = editing?.warehouse?.id ?? warehouses.firstWhereOrNull((w) => w.isDefault)?.id ?? warehouses.firstOrNull?.id;
    } catch (_) {}

    if (editing != null) {
      notes.value = editing!.notes ?? '';
      for (final item in editing!.items) {
        products.add(PlannedProduct(product: item.product, quantity: item.quantity));
        allocations[item.productId] = {};
      }
      for (final store in editing!.stores) {
        selectedStoreIds.add(store.storeId);
        for (final line in store.lines) {
          allocations.putIfAbsent(line.productId, () => {});
          allocations[line.productId]![store.storeId] = line.allocatedQuantity;
        }
      }
    }
    loading.value = false;
  }

  int allocatedFor(String productId) => (allocations[productId] ?? const {}).values.fold(0, (a, b) => a + b);
  int remainingFor(String productId) {
    final planned = products.firstWhereOrNull((p) => p.product.id == productId)?.quantity ?? 0;
    return planned - allocatedFor(productId);
  }

  /// Total allocated to one store, across every product in the order.
  int totalForStore(String storeId) => products.fold(0, (a, p) => a + (allocations[p.product.id]?[storeId] ?? 0));

  /// Available warehouse stock for a product at the order's warehouse, for
  /// context while allocating (0 if unknown/not yet loaded).
  Future<int> warehouseAvailable(String productId) async {
    if (warehouseId.value == null) return 0;
    try {
      final product = await _productRepo.get(productId);
      final row = product.warehouseStock.firstWhereOrNull((s) => s.location.id == warehouseId.value);
      return row?.available ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void addProduct(ProductBrief p) {
    if (products.any((x) => x.product.id == p.id)) return;
    products.add(PlannedProduct(product: p, quantity: 0));
    allocations[p.id] = {};
    version.value++;
  }

  void removeProduct(String productId) {
    products.removeWhere((p) => p.product.id == productId);
    allocations.remove(productId);
    version.value++;
  }

  void setPlannedQuantity(String productId, int qty) {
    products.firstWhereOrNull((p) => p.product.id == productId)?.quantity = qty;
    version.value++;
  }

  void addStore(StoreModel s) {
    if (selectedStoreIds.contains(s.id)) return;
    selectedStoreIds.add(s.id);
    version.value++;
  }

  void removeStore(String storeId) {
    selectedStoreIds.remove(storeId);
    for (final m in allocations.values) {
      m.remove(storeId);
    }
    version.value++;
  }

  void setAllocation(String productId, String storeId, int qty) {
    allocations.putIfAbsent(productId, () => {})[storeId] = qty;
    version.value++;
  }

  /// "Product → multiple stores": replaces every store's allocation for one
  /// product in one go. Any store given a positive quantity is added to the
  /// order automatically; stores set to 0 are cleared but not removed (they
  /// may still hold other products).
  void applyProductAllocation(String productId, Map<String, int> perStore) {
    final map = allocations.putIfAbsent(productId, () => {});
    perStore.forEach((storeId, qty) {
      if (qty > 0 && !selectedStoreIds.contains(storeId)) selectedStoreIds.add(storeId);
      map[storeId] = qty;
    });
    version.value++;
  }

  /// "Store → its products": sets one store's whole product list in one go.
  /// A product new to the order is added with its planned quantity defaulted
  /// to what this store needs; an existing product's planned quantity is left
  /// alone (the admin reconciles "Remaining" across stores separately).
  void applyStoreLines(StoreModel store, Map<ProductBrief, int> lines) {
    if (!selectedStoreIds.contains(store.id)) selectedStoreIds.add(store.id);
    lines.forEach((product, qty) {
      if (!products.any((p) => p.product.id == product.id)) {
        products.add(PlannedProduct(product: product, quantity: qty));
      }
      allocations.putIfAbsent(product.id, () => {})[store.id] = qty;
    });
    // Products that were removed from this store's list in the dialog should
    // no longer carry an allocation for it (but stay in the order for other stores).
    for (final p in products) {
      if (!lines.keys.any((k) => k.id == p.product.id)) {
        allocations[p.product.id]?.remove(store.id);
      }
    }
    version.value++;
  }

  Map<String, dynamic> _payload() => {
        'warehouseId': warehouseId.value,
        'notes': notes.value.trim().isEmpty ? null : notes.value.trim(),
        'items': products.map((p) => {'productId': p.product.id, 'quantity': p.quantity}).toList(),
        'stores': selectedStoreIds
            .map((storeId) => {
                  'storeId': storeId,
                  'items': products
                      .map((p) => {'productId': p.product.id, 'allocatedQuantity': allocations[p.product.id]?[storeId] ?? 0})
                      .where((l) => (l['allocatedQuantity'] as int) > 0)
                      .toList(),
                })
            .toList(),
      };

  Future<PackingOrder?> save() async {
    if (products.isEmpty) {
      Toast.warning('Add at least one product');
      return null;
    }
    if (products.any((p) => p.quantity <= 0)) {
      Toast.warning('Enter a planned quantity greater than 0 for every product');
      return null;
    }
    if (selectedStoreIds.isEmpty) {
      Toast.warning('Add at least one store before saving');
      return null;
    }
    final emptyStores = selectedStoreIds.where((id) => totalForStore(id) == 0).toList();
    if (emptyStores.isNotEmpty) {
      final names = emptyStores.map((id) => allStores.firstWhereOrNull((s) => s.id == id)?.name ?? id).join(', ');
      Toast.warning('$names ${emptyStores.length > 1 ? 'have' : 'has'} no allocated quantity yet. Allocate something or remove ${emptyStores.length > 1 ? 'them' : 'it'}.');
      return null;
    }
    saving.value = true;
    try {
      return isEdit ? await _repo.update(editing!.id, _payload()) : await _repo.create(_payload());
    } catch (e) {
      Toast.error(AppException.from(e).detailedMessage);
      return null;
    } finally {
      saving.value = false;
    }
  }
}
