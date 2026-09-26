import 'package:get/get.dart';

import '../../../core/base/paged_list_controller.dart';
import '../../../core/network/api_response.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/repositories.dart';

class UsersController extends PagedListController<AppUser> {
  UsersController(this._repo, this._storeRepo) : super(tableId: 'users', initialSortBy: 'name', initialSortAsc: true);
  final UserRepository _repo;
  final StoreRepository _storeRepo;

  final stores = <StoreModel>[].obs;
  bool get isAdmin => Get.find<AuthService>().isAdmin;

  @override
  void onInit() {
    super.onInit();
    _storeRepo.all().then(stores.assignAll).catchError((_) {});
  }

  @override
  Future<PageResult<AppUser>> fetchPage(ListQuery query) => _repo.list(query);

  @override
  String idOf(AppUser item) => item.id;

  Future<void> toggleStatus(AppUser u) async {
    try {
      await _repo.setStatus(u.id, u.isActive ? 'INACTIVE' : 'ACTIVE');
      Toast.success(u.isActive ? 'User deactivated' : 'User activated');
      load();
    } catch (e) {
      Toast.fromError(e);
    }
  }

  Future<void> deleteUser(AppUser u) async {
    try {
      final deleted = await _repo.delete(u.id);
      Toast.success(deleted ? 'User deleted' : 'User has activity history and was deactivated instead');
      load();
    } catch (e) {
      Toast.fromError(e);
    }
  }
}
