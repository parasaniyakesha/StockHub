import 'package:get/get.dart';

import '../../../core/base/view_state.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/sales.dart';
import '../../../data/repositories/repositories.dart';

class SaleDetailController extends GetxController {
  SaleDetailController(this._repo, this.saleId);
  final SaleRepository _repo;
  final String saleId;

  final state = ViewState.loading.obs;
  final errorMessage = ''.obs;
  final sale = Rxn<Sale>();
  final acting = false.obs;

  bool get canCancel => Get.find<AuthService>().can('sales.cancel');
  bool get canReturn => Get.find<AuthService>().can('returns.manage');

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    state.value = ViewState.loading;
    try {
      sale.value = await _repo.get(saleId);
      state.value = ViewState.success;
    } catch (e) {
      errorMessage.value = AppException.from(e).message;
      state.value = ViewState.error;
    }
  }

  Future<void> cancel() async {
    final reason = await reasonDialog(title: 'Cancel sale', message: 'Stock will be returned to the store. This cannot be undone.', confirmLabel: 'Cancel sale', destructive: true);
    if (reason == null) return;
    acting.value = true;
    try {
      await _repo.cancel(saleId, reason);
      Toast.success('Sale cancelled');
      load();
    } catch (e) {
      Toast.error(AppException.from(e).detailedMessage);
    } finally {
      acting.value = false;
    }
  }
}
