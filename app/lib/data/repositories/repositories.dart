import 'package:get/get.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_response.dart';
import '../../core/utils/json.dart';
import '../models/catalog.dart';
import '../models/operations.dart';
import '../models/platform.dart';
import '../models/sales.dart';
import '../models/stock.dart';
import '../models/user.dart';
import '../services/api_services.dart';

/// Repositories: the only data access layer the GetX controllers use.
/// Each method maps one API call to typed models. All are registered as
/// permanent singletons in [registerRepositories].

Map<String, dynamic> _data(Json body) => asMap(body['data']);

class UserRepository {
  UserRepository(this._api);
  final UserApi _api;

  Future<PageResult<AppUser>> list(ListQuery q) async => PageResult.fromResponse(await _api.list(q.toParams()), AppUser.fromJson);
  Future<AppUser> get(String id) async => AppUser.fromJson(_data(await _api.get(id)));
  Future<AppUser> create(Map<String, dynamic> body) async => AppUser.fromJson(_data(await _api.create(body)));
  Future<AppUser> update(String id, Map<String, dynamic> body) async => AppUser.fromJson(_data(await _api.update(id, body)));
  Future<AppUser> setStatus(String id, String status) async => AppUser.fromJson(_data(await _api.setStatus(id, status)));
  Future<void> resetPassword(String id, String password) => _api.resetPassword(id, password);

  /// Returns true if hard-deleted, false if the account had activity history and was deactivated instead.
  Future<bool> delete(String id) async => asBool(_data(await _api.delete(id))['deleted']);

  Future<PageResult<AppUser>> managers(ListQuery q) async => PageResult.fromResponse(await _api.managers(q.toParams()), AppUser.fromJson);
  Future<AppUser> setManagerStores(String id, List<String> storeIds) async => AppUser.fromJson(_data(await _api.setManagerStores(id, storeIds)));
  Future<AppUser> setManagerPermissions(String id, List<String> permissions) async =>
      AppUser.fromJson(_data(await _api.setManagerPermissions(id, permissions)));
}

class StoreRepository {
  StoreRepository(this._api);
  final StoreApi _api;

  Future<PageResult<StoreModel>> list(ListQuery q) async => PageResult.fromResponse(await _api.list(q.toParams()), StoreModel.fromJson);

  /// All stores visible to the current user (for dropdowns). Active only by default.
  Future<List<StoreModel>> all({bool activeOnly = true}) async {
    final res = await list(ListQuery(limit: 200, filters: {if (activeOnly) 'status': 'ACTIVE'}, sortBy: 'name', sortOrder: 'asc'));
    return res.items;
  }

  Future<StoreModel> get(String id) async => StoreModel.fromJson(_data(await _api.get(id)));
  Future<StoreModel> create(Map<String, dynamic> body) async => StoreModel.fromJson(_data(await _api.create(body)));
  Future<StoreModel> update(String id, Map<String, dynamic> body) async => StoreModel.fromJson(_data(await _api.update(id, body)));
  Future<StoreModel> setStatus(String id, String status) async => StoreModel.fromJson(_data(await _api.setStatus(id, status)));
  Future<StoreModel> assignManager(String id, String? managerId) async => StoreModel.fromJson(_data(await _api.assignManager(id, managerId)));
  Future<StoreModel> assignUsers(String id, List<String> userIds) async => StoreModel.fromJson(_data(await _api.assignUsers(id, userIds)));

  /// Returns true if hard-deleted, false if the store had related records and was deactivated instead.
  Future<bool> delete(String id) async => asBool(_data(await _api.delete(id))['deleted']);
}

class CategoryRepository {
  CategoryRepository(this._api);
  final CatalogApi _api;

  Future<PageResult<Category>> list(ListQuery q) async => PageResult.fromResponse(await _api.categories(q.toParams()), Category.fromJson);

  /// Entire category tree (unpaginated) for pickers.
  Future<List<Category>> all({bool activeOnly = true}) async {
    final res = await _api.categories({'all': 'true', if (activeOnly) 'status': 'ACTIVE', 'sortBy': 'name', 'sortOrder': 'asc'});
    return asList(res['data']).map((e) => Category.fromJson(asMap(e))).toList();
  }

  Future<Category> get(String id) async => Category.fromJson(_data(await _api.category(id)));
  Future<Category> create(Map<String, dynamic> body) async => Category.fromJson(_data(await _api.createCategory(body)));
  Future<Category> update(String id, Map<String, dynamic> body) async => Category.fromJson(_data(await _api.updateCategory(id, body)));
  Future<Category> setStatus(String id, String status) async => Category.fromJson(_data(await _api.setCategoryStatus(id, status)));
  Future<int> assignProducts(String id, List<String> productIds) async => asInt(_data(await _api.assignProducts(id, productIds))['updated']);
}

class ImportResult {
  const ImportResult({required this.created, required this.updated, required this.errors});
  final int created;
  final int updated;

  /// {row, message}
  final List<Map<String, dynamic>> errors;
}

class ProductRepository {
  ProductRepository(this._api);
  final CatalogApi _api;

  Future<PageResult<Product>> list(ListQuery q) async => PageResult.fromResponse(await _api.products(q.toParams()), Product.fromJson);

  /// Lightweight search for pickers (active products only).
  Future<List<Product>> search(String text, {int limit = 20}) async =>
      (await list(ListQuery(limit: limit, search: text, filters: const {'status': 'ACTIVE'}, sortBy: 'name', sortOrder: 'asc'))).items;

  Future<Product> get(String id) async => Product.fromJson(_data(await _api.product(id)));
  Future<Product> create(Map<String, dynamic> body) async => Product.fromJson(_data(await _api.createProduct(body)));
  Future<Product> update(String id, Map<String, dynamic> body) async => Product.fromJson(_data(await _api.updateProduct(id, body)));
  Future<Product> setStatus(String id, String status) async => Product.fromJson(_data(await _api.setProductStatus(id, status)));

  /// Returns true if hard-deleted, false if it had history and was deactivated.
  Future<bool> delete(String id) async => asBool(_data(await _api.deleteProduct(id))['deleted']);

  /// Nothing is written if any row is invalid; [ImportResult.errors] lists them.
  Future<ImportResult> import(List<Map<String, dynamic>> rows) async {
    final d = _data(await _api.importProducts(rows));
    return ImportResult(
      created: asInt(d['created']),
      updated: asInt(d['updated']),
      errors: asList(d['errors']).map((e) => asMap(e)).toList(),
    );
  }

  Future<DownloadedFile> export(ListQuery q, String format) => _api.exportProducts({...q.toParams(), 'format': format}..remove('page')..remove('limit'));

  Future<List<Warehouse>> warehouses() async => asList((await _api.warehouses())['data']).map((e) => Warehouse.fromJson(asMap(e))).toList();
}

class StockRepository {
  StockRepository(this._api);
  final StockApi _api;

  /// locationType: STORE (default) or WAREHOUSE.
  Future<PageResult<StockBalance>> balances(ListQuery q) async => PageResult.fromResponse(await _api.balances(q.toParams()), StockBalance.fromJson);
  Future<PageResult<StockMovement>> movements(ListQuery q) async => PageResult.fromResponse(await _api.movements(q.toParams()), StockMovement.fromJson);
  Future<DownloadedFile> exportMovements(ListQuery q, String format) =>
      _api.exportMovements({...q.toParams(), 'format': format}..remove('page')..remove('limit'));

  /// items: [{productId, quantity, reason?}]
  Future<void> opening(Map<String, dynamic> body) => _api.opening(body);
  Future<void> purchase(Map<String, dynamic> body) => _api.purchase(body);

  /// items: [{productId, quantity (signed)}], reason required, bucket AVAILABLE|DAMAGED
  Future<void> adjust(Map<String, dynamic> body) => _api.adjust(body);

  /// items: [{productId, quantity, reason}]
  Future<void> reportDamage(Map<String, dynamic> body) => _api.damage(body);
  Future<void> writeOff(Map<String, dynamic> body) => _api.writeOff(body);

  Future<void> submitAvailability(Map<String, dynamic> body) => _api.submitAvailability(body);
  Future<PageResult<StoreAvailability>> availability(ListQuery q) async =>
      PageResult.fromResponse(await _api.availability(q.toParams()), StoreAvailability.fromJson);

  Future<(AvailabilityMatrix, Pagination)> availabilityMatrix(ListQuery q) async {
    final body = await _api.availabilityMatrix(q.toParams());
    final d = _data(body);
    return (
      AvailabilityMatrix(
        stores: asList(d['stores']).map(Ref.fromJson).whereType<Ref>().toList(),
        rows: asList(d['rows']).map((e) => AvailabilityRow.fromJson(asMap(e))).toList(),
      ),
      Pagination.fromJson(body['pagination']),
    );
  }

  /// Removes a zero-balance stock record (the ledger movements behind it are never touched).
  Future<void> deleteBalance(String id, {required bool isWarehouse}) => _api.deleteBalance(id, isWarehouse ? 'WAREHOUSE' : 'STORE');
}

class RequestRepository {
  RequestRepository(this._api);
  final RequestApi _api;

  Future<PageResult<ProductRequest>> list(ListQuery q) async => PageResult.fromResponse(await _api.list(q.toParams()), ProductRequest.fromJson);
  Future<ProductRequest> get(String id) async => ProductRequest.fromJson(_data(await _api.get(id)));

  /// body: {storeId?, notes?, submit, clientRequestId, items:[{productId, requestedQuantity, notes?}]}
  Future<ProductRequest> create(Map<String, dynamic> body) async => ProductRequest.fromJson(_data(await _api.create(body)));
  Future<ProductRequest> update(String id, Map<String, dynamic> body) async => ProductRequest.fromJson(_data(await _api.update(id, body)));
  Future<ProductRequest> submit(String id) async => ProductRequest.fromJson(_data(await _api.submit(id)));
  Future<ProductRequest> startReview(String id) async => ProductRequest.fromJson(_data(await _api.review(id)));

  /// approvals: itemId → approvedQuantity
  Future<ProductRequest> approve(String id, Map<String, int> approvals, {String? reviewNotes}) async => ProductRequest.fromJson(_data(await _api.approve(id, {
        if (reviewNotes != null && reviewNotes.isNotEmpty) 'reviewNotes': reviewNotes,
        'items': approvals.entries.map((e) => {'itemId': e.key, 'approvedQuantity': e.value}).toList(),
      })));
  Future<ProductRequest> reject(String id, String reason) async => ProductRequest.fromJson(_data(await _api.reject(id, reason)));
  Future<ProductRequest> cancel(String id, {String? reason}) async => ProductRequest.fromJson(_data(await _api.cancel(id, reason)));
}

class PackingRepository {
  PackingRepository(this._api);
  final PackingApi _api;

  Future<PageResult<PackingOrder>> list(ListQuery q) async => PageResult.fromResponse(await _api.list(q.toParams()), PackingOrder.fromJson);
  Future<PackingOrder> get(String id) async => PackingOrder.fromJson(_data(await _api.get(id)));

  /// body: {warehouseId?, notes?, items:[{productId, quantity}], stores:[{storeId, items:[{productId, allocatedQuantity}]}]}
  Future<PackingOrder> create(Map<String, dynamic> body) async => PackingOrder.fromJson(_data(await _api.create(body)));
  Future<PackingOrder> fromRequests(List<String> requestIds, {String? notes, String? warehouseId}) async => PackingOrder.fromJson(_data(await _api.fromRequests({
        'requestIds': requestIds,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (warehouseId != null) 'warehouseId': warehouseId,
      })));
  Future<PackingOrder> update(String id, Map<String, dynamic> body) async => PackingOrder.fromJson(_data(await _api.update(id, body)));
  Future<PackingOrder> assign(String id) async => PackingOrder.fromJson(_data(await _api.action(id, 'assign')));
  Future<PackingOrder> startPacking(String id) async => PackingOrder.fromJson(_data(await _api.action(id, 'start-packing')));

  /// packed: allocationLineId → packedQuantity (omitted lines are packed in full)
  Future<PackingOrder> pack(String id, Map<String, int> packed) async => PackingOrder.fromJson(_data(await _api.action(id, 'pack', {
        'lines': packed.entries.map((e) => {'allocationId': e.key, 'packedQuantity': e.value}).toList(),
      })));
  Future<PackingOrder> dispatch(String id) async => PackingOrder.fromJson(_data(await _api.action(id, 'dispatch')));

  /// lines: [{id: lineId, receivedQuantity, damagedQuantity}]; omit to receive everything in good condition.
  Future<PackingOrder> receive(String id, {String? storeId, String? notes, List<Map<String, dynamic>>? lines}) async =>
      PackingOrder.fromJson(_data(await _api.action(id, 'receive', {
        if (storeId != null) 'storeId': storeId,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (lines != null) 'lines': lines,
      })));
  Future<PackingOrder> complete(String id) async => PackingOrder.fromJson(_data(await _api.action(id, 'complete')));
  Future<PackingOrder> cancel(String id, String reason) async => PackingOrder.fromJson(_data(await _api.action(id, 'cancel', {'reason': reason})));
}

class TransferRepository {
  TransferRepository(this._api);
  final TransferApi _api;

  Future<PageResult<StockTransfer>> list(ListQuery q) async => PageResult.fromResponse(await _api.list(q.toParams()), StockTransfer.fromJson);
  Future<StockTransfer> get(String id) async => StockTransfer.fromJson(_data(await _api.get(id)));

  /// body: {sourceType, fromStoreId?, fromWarehouseId?, toStoreId, notes?, clientRequestId, items:[{productId, quantity}]}
  Future<StockTransfer> create(Map<String, dynamic> body) async => StockTransfer.fromJson(_data(await _api.create(body)));

  /// approvals: itemId → approvedQuantity (omit for full approval)
  Future<StockTransfer> approve(String id, [Map<String, int>? approvals]) async => StockTransfer.fromJson(_data(await _api.action(id, 'approve', {
        if (approvals != null) 'items': approvals.entries.map((e) => {'itemId': e.key, 'approvedQuantity': e.value}).toList(),
      })));
  Future<StockTransfer> reject(String id, String reason) async => StockTransfer.fromJson(_data(await _api.action(id, 'reject', {'reason': reason})));
  Future<StockTransfer> dispatch(String id) async => StockTransfer.fromJson(_data(await _api.action(id, 'dispatch')));
  Future<StockTransfer> receive(String id, {String? notes, List<Map<String, dynamic>>? lines}) async => StockTransfer.fromJson(_data(await _api.action(id, 'receive', {
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (lines != null) 'lines': lines,
      })));
  Future<StockTransfer> complete(String id) async => StockTransfer.fromJson(_data(await _api.action(id, 'complete')));
  Future<StockTransfer> cancel(String id, {String? reason}) async => StockTransfer.fromJson(_data(await _api.action(id, 'cancel', {if (reason != null) 'reason': reason})));
}

class SaleRepository {
  SaleRepository(this._api);
  final SalesApi _api;

  Future<PageResult<Sale>> list(ListQuery q) async => PageResult.fromResponse(await _api.list(q.toParams()), Sale.fromJson);
  Future<Sale> get(String id) async => Sale.fromJson(_data(await _api.get(id)));

  /// body: {storeId?, customerName?, customerPhone?, paymentMethod, discount, notes?, clientRequestId, items:[{productId, quantity, unitPrice?, discount}]}
  Future<Sale> create(Map<String, dynamic> body) async => Sale.fromJson(_data(await _api.create(body)));
  Future<Sale> cancel(String id, String reason) async => Sale.fromJson(_data(await _api.cancel(id, reason)));

  Future<PageResult<SaleReturn>> returns(ListQuery q) async => PageResult.fromResponse(await _api.returns(q.toParams()), SaleReturn.fromJson);
  Future<SaleReturn> getReturn(String id) async => SaleReturn.fromJson(_data(await _api.getReturn(id)));

  /// body: {storeId?, saleId?, notes?, clientRequestId, items:[{productId, quantity, condition, reason}]}
  Future<SaleReturn> createReturn(Map<String, dynamic> body) async => SaleReturn.fromJson(_data(await _api.createReturn(body)));
}

class PlatformRepository {
  PlatformRepository(this._api);
  final PlatformApi _api;

  Future<DashboardData> dashboard({String? storeId}) async => DashboardData.fromJson(_data(await _api.dashboard({if (storeId != null) 'storeId': storeId})));

  Future<PageResult<AppNotification>> notifications(ListQuery q) async => PageResult.fromResponse(await _api.notifications(q.toParams()), AppNotification.fromJson);
  Future<int> unreadCount() async => asInt(_data(await _api.unreadCount())['unread']);
  Future<void> markRead(String id) => _api.markRead(id);
  Future<void> markAllRead() => _api.markAllRead();

  Future<AppSettings> settings() async => AppSettings.fromJson(_data(await _api.settings()));
  Future<AppSettings> updateSettings(Map<String, dynamic> patch) async => AppSettings.fromJson(_data(await _api.updateSettings(patch)));

  Future<PageResult<AuditLogEntry>> auditLogs(ListQuery q) async => PageResult.fromResponse(await _api.auditLogs(q.toParams()), AuditLogEntry.fromJson);
  Future<(List<String>, List<String>)> auditFacets() async {
    final d = _data(await _api.auditFacets());
    return (asList(d['modules']).map((e) => e.toString()).toList(), asList(d['actions']).map((e) => e.toString()).toList());
  }

  Future<DownloadedFile> exportAudit(ListQuery q, String format) => _api.exportAudit({...q.toParams(), 'format': format}..remove('page')..remove('limit'));

  /// kind: stock · sales · operations · stores. Filters: type, groupBy, startDate, endDate, storeId, managerId, productId, categoryId, status.
  Future<(ReportData, Pagination)> report(String kind, ListQuery q) async {
    final body = await _api.report(kind, q.toParams());
    return (ReportData.fromJson(_data(body)), Pagination.fromJson(body['pagination']));
  }

  Future<DownloadedFile> exportReport(String kind, ListQuery q, String format) =>
      _api.exportReport(kind, {...q.toParams(), 'format': format}..remove('page')..remove('limit'));
}

/// Registers API services and repositories as permanent singletons.
void registerRepositories(ApiClient client) {
  Get.put(UserRepository(UserApi(client)), permanent: true);
  Get.put(StoreRepository(StoreApi(client)), permanent: true);
  final catalog = CatalogApi(client);
  Get.put(CategoryRepository(catalog), permanent: true);
  Get.put(ProductRepository(catalog), permanent: true);
  Get.put(StockRepository(StockApi(client)), permanent: true);
  Get.put(RequestRepository(RequestApi(client)), permanent: true);
  Get.put(PackingRepository(PackingApi(client)), permanent: true);
  Get.put(TransferRepository(TransferApi(client)), permanent: true);
  Get.put(SaleRepository(SalesApi(client)), permanent: true);
  Get.put(PlatformRepository(PlatformApi(client)), permanent: true);
  Get.put(AuthRepository(AuthApi(client)), permanent: true);
}

class AuthSession {
  const AuthSession({required this.accessToken, required this.refreshToken, required this.user});
  final String accessToken;
  final String refreshToken;
  final AppUser user;
}

class AuthRepository {
  AuthRepository(this._api);
  final AuthApi _api;

  Future<AuthSession> login(String email, String password) async {
    final d = _data(await _api.login(email, password));
    return AuthSession(accessToken: asString(d['accessToken']), refreshToken: asString(d['refreshToken']), user: AppUser.fromJson(asMap(d['user'])));
  }

  Future<void> logout(String? refreshToken) => _api.logout(refreshToken);
  Future<AppUser> me() async => AppUser.fromJson(_data(await _api.me()));
  Future<AppUser> updateProfile({required String name, String? phone}) async =>
      AppUser.fromJson(_data(await _api.updateProfile({'name': name, 'phone': (phone == null || phone.isEmpty) ? null : phone})));
  Future<void> changePassword(String current, String next) => _api.changePassword(current, next);

  /// Returns a reset code only in development when the server has no SMTP configured.
  Future<String?> forgotPassword(String email) async => asStringOrNull(_data(await _api.forgotPassword(email))['devResetToken']);
  Future<void> resetPassword(String token, String password) => _api.resetPassword(token, password);
}
