import 'package:get/get.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/platform.dart';
import '../../../data/repositories/repositories.dart';

class ReportKind {
  ReportKind._();
  static const stock = 'stock';
  static const sales = 'sales';
  static const operations = 'operations';
  static const stores = 'stores';
}

const stockReportTypes = ['current', 'low', 'movement', 'store', 'warehouse', 'damaged', 'returned', 'valuation'];
const salesGroupings = ['day', 'week', 'month', 'year', 'store', 'product', 'category'];
const operationsReportTypes = ['requests', 'packing', 'transfers', 'pending-receipts'];

class ReportsController extends GetxController {
  ReportsController(this._repo, this._storeRepo, this._categoryRepo);
  final PlatformRepository _repo;
  final StoreRepository _storeRepo;
  final CategoryRepository _categoryRepo;

  final kind = ReportKind.sales.obs;
  final type = 'day'.obs; // meaning depends on kind (stock type / sales groupBy / operations type)
  final storeId = RxnString();
  final categoryId = RxnString();
  final startDate = Rxn<DateTime>();
  final endDate = Rxn<DateTime>();

  final loading = true.obs;
  final exporting = false.obs;
  final errorMessage = RxnString();
  final report = Rxn<ReportData>();

  final stores = <StoreModel>[].obs;
  final categories = <Category>[].obs;

  bool get isAdmin => Get.find<AuthService>().isAdmin;
  bool get isStore => Get.find<AuthService>().isStore;

  @override
  void onInit() {
    super.onInit();
    _loadLookups();
    load();
  }

  Future<void> _loadLookups() async {
    try {
      if (!isStore) stores.assignAll(await _storeRepo.all());
      categories.assignAll(await _categoryRepo.all());
    } catch (_) {}
  }

  void setKind(String k) {
    kind.value = k;
    type.value = switch (k) { ReportKind.stock => 'current', ReportKind.sales => 'day', ReportKind.operations => 'requests', _ => '' };
    load();
  }

  void setType(String t) {
    type.value = t;
    load();
  }

  void setStore(String? v) {
    storeId.value = v;
    load();
  }

  void setCategory(String? v) {
    categoryId.value = v;
    load();
  }

  void setDateRange(DateTime? s, DateTime? e) {
    startDate.value = s;
    endDate.value = e;
    load();
  }

  ListQuery get _query => ListQuery(
        limit: 500,
        filters: {
          if (kind.value == ReportKind.stock) 'type': type.value,
          if (kind.value == ReportKind.sales) 'groupBy': type.value,
          if (kind.value == ReportKind.operations) 'type': type.value,
          'storeId': storeId.value,
          'categoryId': categoryId.value,
          'startDate': startDate.value,
          'endDate': endDate.value,
        },
      );

  Future<void> load() async {
    loading.value = true;
    errorMessage.value = null;
    try {
      final (data, _) = await _repo.report(kind.value, _query);
      report.value = data;
    } catch (e) {
      errorMessage.value = AppException.from(e).message;
    } finally {
      loading.value = false;
    }
  }

  Future<void> export(String format) async {
    exporting.value = true;
    try {
      final file = await _repo.exportReport(kind.value, _query, format);
      final saved = await FileUtils.saveDownload(file);
      if (saved != null) Toast.success('Exported to $saved');
    } catch (e) {
      Toast.fromError(e);
    } finally {
      exporting.value = false;
    }
  }
}
