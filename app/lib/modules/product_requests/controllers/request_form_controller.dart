import 'package:get/get.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/widgets/quantity_lines_editor.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/operations.dart';
import '../../../data/repositories/repositories.dart';

class RequestFormController extends GetxController {
  RequestFormController(this._repo, this._storeRepo, {this.editing});
  final RequestRepository _repo;
  final StoreRepository _storeRepo;
  final ProductRequest? editing;
  bool get isEdit => editing != null;

  final lines = <QuantityLine>[].obs;
  final notes = ''.obs;
  final storeId = RxnString();
  final stores = <StoreModel>[].obs;
  final saving = false.obs;
  final loading = true.obs;
  final _clientRequestId = newClientRequestId();

  bool get isStore => Get.find<AuthService>().isStore;

  @override
  void onInit() {
    super.onInit();
    _init();
  }

  Future<void> _init() async {
    if (editing != null) {
      lines.assignAll(editing!.items.map((i) => QuantityLine(product: i.product, quantity: i.requestedQuantity, note: i.notes)));
      notes.value = editing!.notes ?? '';
      storeId.value = editing!.store.id;
    }
    if (!isStore) {
      try {
        stores.assignAll(await _storeRepo.all());
      } catch (_) {}
    }
    loading.value = false;
  }

  Future<ProductRequest?> save({required bool submit}) async {
    if (lines.isEmpty) {
      Toast.warning('Add at least one product');
      return null;
    }
    if (!isStore && storeId.value == null) {
      Toast.warning('Select a store');
      return null;
    }
    saving.value = true;
    try {
      final body = {
        if (!isStore) 'storeId': storeId.value,
        'notes': notes.value.trim().isEmpty ? null : notes.value.trim(),
        'submit': submit,
        if (!isEdit) 'clientRequestId': _clientRequestId,
        'items': lines.map((l) => {'productId': l.product.id, 'requestedQuantity': l.quantity, if (l.note?.isNotEmpty == true) 'notes': l.note}).toList(),
      };
      final result = isEdit ? await _repo.update(editing!.id, body) : await _repo.create(body);
      if (isEdit && submit) return _repo.submit(result.id);
      return result;
    } catch (e) {
      Toast.error(AppException.from(e).detailedMessage);
      return null;
    } finally {
      saving.value = false;
    }
  }
}
