import 'package:get/get.dart';

import '../../../core/base/view_state.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/repositories.dart';

class StoreDetailController extends GetxController {
  StoreDetailController(this._repo, this._userRepo, this.storeId);
  final StoreRepository _repo;
  final UserRepository _userRepo;
  final String storeId;

  final state = ViewState.loading.obs;
  final errorMessage = ''.obs;
  final store = Rxn<StoreModel>();
  final managers = <AppUser>[].obs;

  @override
  void onInit() {
    super.onInit();
    load();
    _userRepo.managers(const ListQuery(limit: 200, filters: {'status': 'ACTIVE'})).then((r) => managers.assignAll(r.items)).catchError((_) {});
  }

  Future<void> load() async {
    state.value = ViewState.loading;
    try {
      store.value = await _repo.get(storeId);
      state.value = ViewState.success;
    } catch (e) {
      errorMessage.value = AppException.from(e).message;
      state.value = ViewState.error;
    }
  }

  Future<void> toggleUserStatus(String userId, bool currentlyActive) async {
    // Delegates to the user repository via UsersController pattern would be
    // preferable long-term; kept local for the read-mostly store detail page.
    try {
      await Get.find<UserRepository>().setStatus(userId, currentlyActive ? 'INACTIVE' : 'ACTIVE');
      Toast.success('User updated');
      load();
    } catch (e) {
      Toast.fromError(e);
    }
  }
}
