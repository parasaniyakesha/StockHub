import 'package:get/get.dart';

import '../../../core/base/paged_list_controller.dart';
import '../../../core/network/api_response.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/repositories.dart';

class ManagersController extends PagedListController<AppUser> {
  ManagersController(this._repo, this._storeRepo) : super(tableId: 'managers', initialSortBy: 'name', initialSortAsc: true) {
    limit.value = 50;
  }
  final UserRepository _repo;
  final StoreRepository _storeRepo;

  final stores = <StoreModel>[].obs;

  @override
  void onInit() {
    super.onInit();
    _storeRepo.all().then(stores.assignAll).catchError((_) {});
  }

  @override
  Future<PageResult<AppUser>> fetchPage(ListQuery query) => _repo.managers(query);

  @override
  String idOf(AppUser item) => item.id;

  Future<void> setStores(String managerId, List<String> storeIds) async {
    try {
      await _repo.setManagerStores(managerId, storeIds);
      Toast.success('Assigned stores updated');
      load();
    } catch (e) {
      Toast.fromError(e);
    }
  }

  Future<void> setPermissions(String managerId, List<String> permissions) async {
    try {
      await _repo.setManagerPermissions(managerId, permissions);
      Toast.success('Permissions updated');
      load();
    } catch (e) {
      Toast.fromError(e);
    }
  }

  Future<void> deleteManager(AppUser manager) async {
    try {
      final deleted = await _repo.delete(manager.id);
      Toast.success(deleted ? 'Manager deleted' : 'Manager has activity history and was deactivated instead');
      load();
    } catch (e) {
      Toast.fromError(e);
    }
  }
}
