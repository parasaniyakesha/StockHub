import 'package:get/get.dart';

import '../../../core/base/paged_list_controller.dart';
import '../../../core/network/api_response.dart';
import '../../../core/session/auth_service.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/operations.dart';
import '../../../data/repositories/repositories.dart';

class PackingOrdersController extends PagedListController<PackingOrder> {
  PackingOrdersController(this._repo, this._storeRepo) : super(tableId: 'packing_orders', initialSortBy: 'createdAt', initialSortAsc: false);
  final PackingRepository _repo;
  final StoreRepository _storeRepo;

  final stores = <StoreModel>[].obs;
  bool get isStore => Get.find<AuthService>().isStore;
  bool get canManage => Get.find<AuthService>().can('packing.manage');

  @override
  void onInit() {
    super.onInit();
    if (!isStore) _storeRepo.all().then(stores.assignAll).catchError((_) {});
  }

  @override
  Future<PageResult<PackingOrder>> fetchPage(ListQuery query) => _repo.list(query);

  @override
  String idOf(PackingOrder item) => item.id;
}
