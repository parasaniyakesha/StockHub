import 'package:get/get.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/widgets/quantity_lines_editor.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/operations.dart';
import '../../../data/repositories/repositories.dart';

class TransferFormController extends GetxController {
  TransferFormController(this._repo, this._storeRepo, this._productRepo);
  final TransferRepository _repo;
  final StoreRepository _storeRepo;
  final ProductRepository _productRepo;

  final loading = true.obs;
  final saving = false.obs;
  final notes = ''.obs;
  final sourceType = 'WAREHOUSE'.obs; // WAREHOUSE or STORE
  final fromStoreId = RxnString();
  final toStoreId = RxnString();
  final lines = <QuantityLine>[].obs;
  final stores = <StoreModel>[].obs;
  final warehouses = <Warehouse>[].obs;
  final _clientRequestId = newClientRequestId();

  bool get isStore => Get.find<AuthService>().isStore;
  String? get myStoreId => Get.find<AuthService>().current?.storeId;

  @override
  void onInit() {
    super.onInit();
    _init();
  }

  Future<void> _init() async {
    try {
      stores.assignAll(await _storeRepo.all());
      warehouses.assignAll(await _productRepo.warehouses());
    } catch (_) {}
    if (isStore) {
      // A store can request stock INTO itself (from warehouse or another store)
      // or offer stock OUT of itself. Default: incoming from the warehouse.
      toStoreId.value = myStoreId;
    }
    loading.value = false;
  }

  /// For a store user, whether they are requesting stock in or sending it out.
  final direction = 'IN'.obs;
  void setDirection(String d) {
    direction.value = d;
    if (isStore) {
      if (d == 'IN') {
        toStoreId.value = myStoreId;
        fromStoreId.value = null;
      } else {
        fromStoreId.value = myStoreId;
        toStoreId.value = null;
        sourceType.value = 'STORE';
      }
    }
  }

  Future<StockTransfer?> save() async {
    if (lines.isEmpty) {
      Toast.warning('Add at least one product');
      return null;
    }
    if (toStoreId.value == null) {
      Toast.warning('Select the destination store');
      return null;
    }
    if (sourceType.value == 'STORE' && fromStoreId.value == null) {
      Toast.warning('Select the source store');
      return null;
    }
    saving.value = true;
    try {
      return await _repo.create({
        'sourceType': sourceType.value,
        if (sourceType.value == 'STORE') 'fromStoreId': fromStoreId.value,
        'toStoreId': toStoreId.value,
        'notes': notes.value.trim().isEmpty ? null : notes.value.trim(),
        'clientRequestId': _clientRequestId,
        'items': lines.map((l) => {'productId': l.product.id, 'quantity': l.quantity}).toList(),
      });
    } catch (e) {
      Toast.error(AppException.from(e).detailedMessage);
      return null;
    } finally {
      saving.value = false;
    }
  }
}
