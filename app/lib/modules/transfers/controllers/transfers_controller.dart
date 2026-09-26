import 'package:get/get.dart';

import '../../../core/base/paged_list_controller.dart';
import '../../../core/network/api_response.dart';
import '../../../core/session/auth_service.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/operations.dart';
import '../../../data/repositories/repositories.dart';

class TransfersController extends PagedListController<StockTransfer> {
  TransfersController(this._repo, this._storeRepo) : super(tableId: 'transfers', initialSortBy: 'createdAt', initialSortAsc: false);
  final TransferRepository _repo;
  final StoreRepository _storeRepo;

  final stores = <StoreModel>[].obs;
  bool get isStore => Get.find<AuthService>().isStore;

  @override
  void onInit() {
    super.onInit();
    if (!isStore) _storeRepo.all().then(stores.assignAll).catchError((_) {});
  }

  @override
  Future<PageResult<StockTransfer>> fetchPage(ListQuery query) => _repo.list(query);

  @override
  String idOf(StockTransfer item) => item.id;
}
