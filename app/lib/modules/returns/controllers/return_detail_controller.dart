import 'package:get/get.dart';

import '../../../core/base/view_state.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/models/sales.dart';
import '../../../data/repositories/repositories.dart';

class ReturnDetailController extends GetxController {
  ReturnDetailController(this._repo, this.returnId);
  final SaleRepository _repo;
  final String returnId;

  final state = ViewState.loading.obs;
  final errorMessage = ''.obs;
  final saleReturn = Rxn<SaleReturn>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    state.value = ViewState.loading;
    try {
      saleReturn.value = await _repo.getReturn(returnId);
      state.value = ViewState.success;
    } catch (e) {
      errorMessage.value = AppException.from(e).message;
      state.value = ViewState.error;
    }
  }
}
