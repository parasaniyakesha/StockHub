import 'package:get/get.dart';

import '../../../core/base/paged_list_controller.dart';
import '../../../core/network/api_response.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/repositories/repositories.dart';

class CategoriesController extends PagedListController<Category> {
  CategoriesController(this._repo) : super(tableId: 'categories', initialSortBy: 'name', initialSortAsc: true) {
    limit.value = 50;
  }
  final CategoryRepository _repo;

  final allCategories = <Category>[].obs;

  @override
  void onInit() {
    super.onInit();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      allCategories.assignAll(await _repo.all(activeOnly: false));
    } catch (_) {}
  }

  @override
  Future<PageResult<Category>> fetchPage(ListQuery query) => _repo.list(query);

  @override
  String idOf(Category item) => item.id;

  @override
  Future<void> load() async {
    await super.load();
    await _loadAll();
  }

  Future<void> toggleStatus(Category cat) async {
    try {
      await _repo.setStatus(cat.id, cat.isActive ? 'INACTIVE' : 'ACTIVE');
      Toast.success(cat.isActive ? 'Category deactivated' : 'Category activated');
      load();
    } catch (e) {
      Toast.fromError(e);
    }
  }
}
