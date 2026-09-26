import 'package:get/get.dart';

import '../../../core/base/paged_list_controller.dart';
import '../../../core/network/api_response.dart';
import '../../../core/session/auth_service.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/sales.dart';
import '../../../data/repositories/repositories.dart';

class ReturnsController extends PagedListController<SaleReturn> {
  ReturnsController(this._repo, this._storeRepo) : super(tableId: 'returns', initialSortBy: 'createdAt', initialSortAsc: false);
  final SaleRepository _repo;
  final StoreRepository _storeRepo;

  final stores = <StoreModel>[].obs;
  bool get isStore => Get.find<AuthService>().isStore;
  bool get canCreate => Get.find<AuthService>().can('returns.manage');

  @override
  void onInit() {
    super.onInit();
    if (!isStore) _storeRepo.all().then(stores.assignAll).catchError((_) {});
  }

  @override
  Future<PageResult<SaleReturn>> fetchPage(ListQuery query) => _repo.returns(query);

  @override
  String idOf(SaleReturn item) => item.id;
}
