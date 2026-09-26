import 'package:get/get.dart';

import '../../../core/base/view_state.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/models/catalog.dart';
import '../../../data/repositories/repositories.dart';

class ProductDetailController extends GetxController {
  ProductDetailController(this._repo, this._categoryRepo, this.productId);
  final ProductRepository _repo;
  final CategoryRepository _categoryRepo;
  final String productId;

  final state = ViewState.loading.obs;
  final errorMessage = ''.obs;
  final product = Rxn<Product>();
  final categories = <Category>[].obs;

  @override
  void onInit() {
    super.onInit();
    load();
    _categoryRepo.all().then(categories.assignAll).catchError((_) {});
  }

  Future<void> load() async {
    state.value = ViewState.loading;
    try {
      product.value = await _repo.get(productId);
      state.value = ViewState.success;
    } catch (e) {
      errorMessage.value = AppException.from(e).message;
      state.value = ViewState.error;
    }
  }
}
