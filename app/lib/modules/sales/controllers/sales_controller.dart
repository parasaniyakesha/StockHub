import 'package:get/get.dart';

import '../../../core/base/paged_list_controller.dart';
import '../../../core/network/api_response.dart';
import '../../../core/session/auth_service.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/sales.dart';
import '../../../data/repositories/repositories.dart';

class SalesController extends PagedListController<Sale> {
  SalesController(this._repo, this._storeRepo) : super(tableId: 'sales', initialSortBy: 'createdAt', initialSortAsc: false);
  final SaleRepository _repo;
  final StoreRepository _storeRepo;

  final stores = <StoreModel>[].obs;
  bool get isStore => Get.find<AuthService>().isStore;
  bool get canCreate => Get.find<AuthService>().can('sales.create');

  @override
  void onInit() {
    super.onInit();
    if (!isStore) _storeRepo.all().then(stores.assignAll).catchError((_) {});
  }

  @override
  Future<PageResult<Sale>> fetchPage(ListQuery query) => _repo.list(query);

  @override
  String idOf(Sale item) => item.id;

  SalesSummary? get summary => extra['summary'] == null ? null : SalesSummary.fromJson(extra['summary']);
}
