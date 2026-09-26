import 'package:get/get.dart';

import '../../../core/base/paged_list_controller.dart';
import '../../../core/network/api_response.dart';
import '../../../core/session/auth_service.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/operations.dart';
import '../../../data/repositories/repositories.dart';

class RequestsController extends PagedListController<ProductRequest> {
  RequestsController(this._repo, this._storeRepo) : super(tableId: 'requests', initialSortBy: 'createdAt', initialSortAsc: false);
  final RequestRepository _repo;
  final StoreRepository _storeRepo;

  final stores = <StoreModel>[].obs;
  bool get isStore => Get.find<AuthService>().isStore;

  @override
  void onInit() {
    super.onInit();
    if (!isStore) _storeRepo.all().then(stores.assignAll).catchError((_) {});
  }

  @override
  Future<PageResult<ProductRequest>> fetchPage(ListQuery query) => _repo.list(query);

  @override
  String idOf(ProductRequest item) => item.id;
}
