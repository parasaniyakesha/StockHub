import 'package:get/get.dart';

import '../../../core/base/paged_list_controller.dart';
import '../../../core/network/api_response.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/stock.dart';
import '../../../data/repositories/repositories.dart';

class StockController extends PagedListController<StockBalance> {
  StockController(this._repo, this._storeRepo, this._categoryRepo, this._productRepo) : super(tableId: 'stock', initialSortBy: 'product', initialSortAsc: true) {
    if (isStore) filters['locationType'] = 'STORE';
  }
  final StockRepository _repo;
  final StoreRepository _storeRepo;
  final CategoryRepository _categoryRepo;
  final ProductRepository _productRepo;

  final stores = <StoreModel>[].obs;
  final categories = <Category>[].obs;
  final warehouses = <Warehouse>[].obs;

  bool get isAdmin => Get.find<AuthService>().isAdmin;
  bool get isStore => Get.find<AuthService>().isStore;
  String get locationType => (filters['locationType'] as String?) ?? 'STORE';

  @override
  void onInit() {
    super.onInit();
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    try {
      if (!isStore) stores.assignAll(await _storeRepo.all());
      categories.assignAll(await _categoryRepo.all());
      if (isAdmin) warehouses.assignAll(await _productRepo.warehouses());
    } catch (_) {}
  }

  void setLocationType(String type) {
    filters['locationType'] = type;
    if (type == 'WAREHOUSE') filters.remove('storeId');
    page.value = 1;
    load();
  }

  @override
  Future<PageResult<StockBalance>> fetchPage(ListQuery query) => _repo.balances(query);

  @override
  String idOf(StockBalance item) => item.id;

  /// Removes a stale zero-balance stock record. The ledger movements behind
  /// it are permanent and untouched - this only tidies up the balance row.
  Future<void> deleteBalance(StockBalance b) async {
    try {
      await _repo.deleteBalance(b.id, isWarehouse: locationType == 'WAREHOUSE');
      Toast.success('Stock record removed');
      load();
    } catch (e) {
      Toast.fromError(e);
    }
  }
}
