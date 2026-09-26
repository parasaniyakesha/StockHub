import 'package:get/get.dart';

import '../../../core/base/paged_list_controller.dart';
import '../../../core/network/api_response.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../../../data/repositories/repositories.dart';

class ProductsController extends PagedListController<Product> {
  ProductsController(this._repo, this._categoryRepo) : super(tableId: 'products', initialSortBy: 'name', initialSortAsc: true);
  final ProductRepository _repo;
  final CategoryRepository _categoryRepo;

  final categories = <Category>[].obs;
  final exporting = false.obs;
  final importing = false.obs;

  bool get isStore => Get.find<AuthService>().isStore;
  bool get canManage => Get.find<AuthService>().can('products.manage');

  @override
  void onInit() {
    super.onInit();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      categories.assignAll(await _categoryRepo.all());
    } catch (_) {}
  }

  @override
  Future<PageResult<Product>> fetchPage(ListQuery query) => _repo.list(query);

  @override
  String idOf(Product item) => item.id;

  Future<void> export(String format) async {
    exporting.value = true;
    try {
      final file = await _repo.export(query, format);
      final saved = await FileUtils.saveDownload(file);
      if (saved != null) Toast.success('Exported to $saved');
    } catch (e) {
      Toast.fromError(e);
    } finally {
      exporting.value = false;
    }
  }

  Future<void> importCsv() async {
    final rows = await FileUtils.pickCsvRows();
    if (rows == null) return;
    if (rows.isEmpty) return Toast.warning('The selected file has no data rows.');
    importing.value = true;
    try {
      final result = await _repo.import(rows.map(_normalizeImportRow).toList());
      if (result.errors.isNotEmpty) {
        Toast.error('Import failed on ${result.errors.length} row(s). First: row ${result.errors.first['row']} - ${result.errors.first['message']}');
      } else {
        Toast.success('Imported: ${result.created} created, ${result.updated} updated');
        load();
      }
    } catch (e) {
      Toast.fromError(e);
    } finally {
      importing.value = false;
    }
  }

  Map<String, dynamic> _normalizeImportRow(Map<String, String> row) {
    // Accept a few common header spellings from a CSV template.
    String? v(List<String> keys) {
      for (final k in keys) {
        if (row.containsKey(k) && row[k]!.isNotEmpty) return row[k];
      }
      return null;
    }

    return {
      'name': v(['name', 'Name']),
      'sku': v(['sku', 'SKU']),
      'barcode': v(['barcode', 'Barcode']),
      'categoryCode': v(['categoryCode', 'Category', 'category']),
      'brand': v(['brand', 'Brand']),
      'unit': v(['unit', 'Unit']) ?? 'PCS',
      'description': v(['description', 'Description']),
      'purchasePrice': v(['purchasePrice', 'Purchase Price', 'cost']),
      'sellingPrice': v(['sellingPrice', 'Selling Price', 'price']),
      'taxRate': v(['taxRate', 'Tax Rate', 'tax']) ?? '0',
      'minimumStock': v(['minimumStock', 'Minimum Stock', 'min']) ?? '0',
      'maximumStock': v(['maximumStock', 'Maximum Stock', 'max']),
    };
  }

  Future<void> toggleStatus(Product p) async {
    try {
      await _repo.setStatus(p.id, p.isActive ? 'INACTIVE' : 'ACTIVE');
      Toast.success(p.isActive ? 'Product deactivated' : 'Product activated');
      load();
    } catch (e) {
      Toast.fromError(e);
    }
  }

  Future<void> deleteProduct(Product p) async {
    try {
      final deleted = await _repo.delete(p.id);
      Toast.success(deleted ? 'Product deleted' : 'Product has stock history and was deactivated instead');
      load();
    } catch (e) {
      Toast.fromError(e);
    }
  }
}
