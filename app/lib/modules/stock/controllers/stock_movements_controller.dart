import 'package:get/get.dart';

import '../../../core/base/paged_list_controller.dart';
import '../../../core/network/api_response.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/stock.dart';
import '../../../data/repositories/repositories.dart';

class StockMovementsController extends PagedListController<StockMovement> {
  StockMovementsController(this._repo, this._storeRepo, this._productRepo) : super(tableId: 'stock_movements', initialSortBy: 'createdAt', initialSortAsc: false) {
    final productId = Get.parameters['productId'];
    if (productId != null && productId.isNotEmpty) filters['productId'] = productId;
  }
  final StockRepository _repo;
  final StoreRepository _storeRepo;
  final ProductRepository _productRepo;

  final stores = <StoreModel>[].obs;
  final warehouses = <Warehouse>[].obs;
  final exporting = false.obs;

  bool get isStore => Get.find<AuthService>().isStore;

  @override
  void onInit() {
    super.onInit();
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    try {
      if (!isStore) stores.assignAll(await _storeRepo.all());
      if (Get.find<AuthService>().isAdmin) warehouses.assignAll(await _productRepo.warehouses());
    } catch (_) {}
  }

  @override
  Future<PageResult<StockMovement>> fetchPage(ListQuery query) => _repo.movements(query);

  @override
  String idOf(StockMovement item) => item.id;

  Future<void> export(String format) async {
    exporting.value = true;
    try {
      final file = await _repo.exportMovements(query, format);
      final saved = await FileUtils.saveDownload(file);
      if (saved != null) Toast.success('Exported to $saved');
    } catch (e) {
      Toast.fromError(e);
    } finally {
      exporting.value = false;
    }
  }
}
