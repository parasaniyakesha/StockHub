import 'package:get/get.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/session/auth_service.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/platform.dart';
import '../../../data/repositories/repositories.dart';

class DashboardController extends GetxController {
  DashboardController(this._repo, this._storeRepo);
  final PlatformRepository _repo;
  final StoreRepository _storeRepo;

  final loading = true.obs;
  final errorMessage = RxnString();
  final data = Rxn<DashboardData>();

  /// Manager-only store filter (null = all assigned stores).
  final storeFilter = RxnString();
  final stores = <StoreModel>[].obs;

  bool get isAdmin => Get.find<AuthService>().isAdmin;
  bool get isManager => Get.find<AuthService>().isManager;

  @override
  void onInit() {
    super.onInit();
    if (isManager) _loadStores();
    load();
  }

  Future<void> _loadStores() async {
    try {
      stores.assignAll(await _storeRepo.all());
    } catch (_) {}
  }

  Future<void> load() async {
    loading.value = true;
    errorMessage.value = null;
    try {
      data.value = await _repo.dashboard(storeId: storeFilter.value);
    } catch (e) {
      errorMessage.value = AppException.from(e).message;
    } finally {
      loading.value = false;
    }
  }

  void setStore(String? storeId) {
    storeFilter.value = storeId;
    load();
  }
}
