import 'package:get/get.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/widgets/quantity_lines_editor.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/stock.dart';
import '../../../data/repositories/repositories.dart';

class StockAvailabilityController extends GetxController {
  StockAvailabilityController(this._repo);
  final StockRepository _repo;

  bool get isAdmin => Get.find<AuthService>().isAdmin || Get.find<AuthService>().isManager;

  // Matrix (admin/manager view)
  final matrixLoading = true.obs;
  final matrixError = RxnString();
  final matrix = Rxn<AvailabilityMatrix>();
  final matrixSearch = ''.obs;

  // Submission (store view)
  final lines = <QuantityLine>[].obs;
  final submitting = false.obs;
  final myAvailability = <StoreAvailability>[].obs;
  final loadingMine = true.obs;

  @override
  void onInit() {
    super.onInit();
    isAdmin ? loadMatrix() : loadMine();
  }

  Future<void> loadMatrix() async {
    matrixLoading.value = true;
    matrixError.value = null;
    try {
      final (m, _) = await _repo.availabilityMatrix(ListQuery(limit: 100, search: matrixSearch.value));
      matrix.value = m;
    } catch (e) {
      matrixError.value = AppException.from(e).message;
    } finally {
      matrixLoading.value = false;
    }
  }

  Future<void> loadMine() async {
    loadingMine.value = true;
    try {
      final res = await _repo.availability(const ListQuery(limit: 200));
      myAvailability.assignAll(res.items);
      lines.assignAll(res.items.map((a) => QuantityLine(product: a.product, quantity: a.quantity)));
    } catch (_) {
    } finally {
      loadingMine.value = false;
    }
  }

  Future<void> submit(String? notes) async {
    if (lines.isEmpty) return Toast.warning('Add at least one product');
    submitting.value = true;
    try {
      await _repo.submitAvailability({
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'items': lines.map((l) => {'productId': l.product.id, 'quantity': l.quantity}).toList(),
      });
      Toast.success('Availability submitted');
      loadMine();
    } catch (e) {
      Toast.fromError(e);
    } finally {
      submitting.value = false;
    }
  }
}
