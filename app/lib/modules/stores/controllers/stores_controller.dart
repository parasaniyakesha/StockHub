import 'package:get/get.dart';

import '../../../core/base/paged_list_controller.dart';
import '../../../core/network/api_response.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/repositories.dart';

class StoresController extends PagedListController<StoreModel> {
  StoresController(this._repo, this._userRepo) : super(tableId: 'stores', initialSortBy: 'name', initialSortAsc: true);
  final StoreRepository _repo;
  final UserRepository _userRepo;

  final managers = <AppUser>[].obs;

  @override
  void onInit() {
    super.onInit();
    _loadManagers();
  }

  Future<void> _loadManagers() async {
    try {
      final res = await _userRepo.managers(const ListQuery(limit: 200, filters: {'status': 'ACTIVE'}));
      managers.assignAll(res.items);
    } catch (_) {}
  }

  @override
  Future<PageResult<StoreModel>> fetchPage(ListQuery query) => _repo.list(query);

  @override
  String idOf(StoreModel item) => item.id;

  Future<void> toggleStatus(StoreModel s) async {
    try {
      await _repo.setStatus(s.id, s.isActive ? 'INACTIVE' : 'ACTIVE');
      Toast.success(s.isActive ? 'Store deactivated' : 'Store activated');
      load();
    } catch (e) {
      Toast.fromError(e);
    }
  }

  Future<void> deleteStore(StoreModel s) async {
    try {
      final deleted = await _repo.delete(s.id);
      Toast.success(deleted ? 'Store deleted' : 'Store has related records and was deactivated instead');
      load();
    } catch (e) {
      Toast.fromError(e);
    }
  }
}
