import '../../core/network/api_client.dart';

/// API services: one thin class per backend resource. They only know endpoint
/// paths and payload shapes and return raw JSON; repositories turn that into
/// models. Nothing in `modules/` may call these (or Dio) directly.

class AuthApi {
  AuthApi(this._c);
  final ApiClient _c;
  Future<Json> login(String email, String password) => _c.post('/auth/login', body: {'email': email, 'password': password}, skipAuth: true);
  Future<Json> logout(String? refreshToken, {bool allDevices = false}) =>
      _c.post('/auth/logout', body: {if (refreshToken != null) 'refreshToken': refreshToken, 'allDevices': allDevices});
  Future<Json> me() => _c.get('/auth/me');
  Future<Json> updateProfile(Json body) => _c.put('/auth/me', body: body);
  Future<Json> changePassword(String current, String next) => _c.put('/auth/change-password', body: {'currentPassword': current, 'newPassword': next});
  Future<Json> forgotPassword(String email) => _c.post('/auth/forgot-password', body: {'email': email}, skipAuth: true);
  Future<Json> resetPassword(String token, String password) => _c.post('/auth/reset-password', body: {'token': token, 'newPassword': password}, skipAuth: true);
}

class UserApi {
  UserApi(this._c);
  final ApiClient _c;
  Future<Json> list(Map<String, dynamic> q) => _c.get('/users', query: q);
  Future<Json> get(String id) => _c.get('/users/$id');
  Future<Json> create(Json body) => _c.post('/users', body: body);
  Future<Json> update(String id, Json body) => _c.put('/users/$id', body: body);
  Future<Json> setStatus(String id, String status) => _c.patch('/users/$id/status', body: {'status': status});
  Future<Json> resetPassword(String id, String password) => _c.put('/users/$id/password', body: {'newPassword': password});
  Future<Json> delete(String id) => _c.delete('/users/$id');
  Future<Json> managers(Map<String, dynamic> q) => _c.get('/managers', query: q);
  Future<Json> setManagerStores(String id, List<String> storeIds) => _c.put('/managers/$id/stores', body: {'storeIds': storeIds});
  Future<Json> setManagerPermissions(String id, List<String> permissions) => _c.put('/managers/$id/permissions', body: {'permissions': permissions});
}

class StoreApi {
  StoreApi(this._c);
  final ApiClient _c;
  Future<Json> list(Map<String, dynamic> q) => _c.get('/stores', query: q);
  Future<Json> get(String id) => _c.get('/stores/$id');
  Future<Json> create(Json body) => _c.post('/stores', body: body);
  Future<Json> update(String id, Json body) => _c.put('/stores/$id', body: body);
  Future<Json> setStatus(String id, String status) => _c.patch('/stores/$id/status', body: {'status': status});
  Future<Json> assignManager(String id, String? managerId) => _c.put('/stores/$id/manager', body: {'managerId': managerId});
  Future<Json> assignUsers(String id, List<String> userIds) => _c.put('/stores/$id/users', body: {'userIds': userIds});
  Future<Json> delete(String id) => _c.delete('/stores/$id');
}

class CatalogApi {
  CatalogApi(this._c);
  final ApiClient _c;
  // Categories
  Future<Json> categories(Map<String, dynamic> q) => _c.get('/categories', query: q);
  Future<Json> category(String id) => _c.get('/categories/$id');
  Future<Json> createCategory(Json body) => _c.post('/categories', body: body);
  Future<Json> updateCategory(String id, Json body) => _c.put('/categories/$id', body: body);
  Future<Json> setCategoryStatus(String id, String status) => _c.patch('/categories/$id/status', body: {'status': status});
  Future<Json> assignProducts(String id, List<String> productIds) => _c.put('/categories/$id/products', body: {'productIds': productIds});
  // Products
  Future<Json> products(Map<String, dynamic> q) => _c.get('/products', query: q);
  Future<Json> product(String id) => _c.get('/products/$id');
  Future<Json> createProduct(Json body) => _c.post('/products', body: body);
  Future<Json> updateProduct(String id, Json body) => _c.put('/products/$id', body: body);
  Future<Json> setProductStatus(String id, String status) => _c.patch('/products/$id/status', body: {'status': status});
  Future<Json> deleteProduct(String id) => _c.delete('/products/$id');
  Future<Json> importProducts(List<Map<String, dynamic>> rows) => _c.post('/products/import', body: {'rows': rows});
  Future<DownloadedFile> exportProducts(Map<String, dynamic> q) => _c.download('/products/export', query: q, fallbackName: 'products.csv');
  // Warehouses
  Future<Json> warehouses() => _c.get('/warehouses');
}

class StockApi {
  StockApi(this._c);
  final ApiClient _c;
  Future<Json> balances(Map<String, dynamic> q) => _c.get('/stock', query: q);
  Future<Json> movements(Map<String, dynamic> q) => _c.get('/stock/movements', query: q);
  Future<DownloadedFile> exportMovements(Map<String, dynamic> q) => _c.download('/stock/movements/export', query: q, fallbackName: 'stock-movements.csv');
  Future<Json> opening(Json body) => _c.post('/stock/opening', body: body);
  Future<Json> purchase(Json body) => _c.post('/stock/purchases', body: body);
  Future<Json> adjust(Json body) => _c.post('/stock/adjustments', body: body);
  Future<Json> damage(Json body) => _c.post('/stock/damage', body: body);
  Future<Json> writeOff(Json body) => _c.post('/stock/damage/write-off', body: body);
  Future<Json> submitAvailability(Json body) => _c.post('/stock/availability', body: body);
  Future<Json> availability(Map<String, dynamic> q) => _c.get('/stock/availability', query: q);
  Future<Json> availabilityMatrix(Map<String, dynamic> q) => _c.get('/stock/availability/matrix', query: q);
  Future<Json> deleteBalance(String id, String locationType) => _c.delete('/stock/$id', query: {'locationType': locationType});
}

class RequestApi {
  RequestApi(this._c);
  final ApiClient _c;
  Future<Json> list(Map<String, dynamic> q) => _c.get('/product-requests', query: q);
  Future<Json> get(String id) => _c.get('/product-requests/$id');
  Future<Json> create(Json body) => _c.post('/product-requests', body: body);
  Future<Json> update(String id, Json body) => _c.put('/product-requests/$id', body: body);
  Future<Json> submit(String id) => _c.put('/product-requests/$id/submit');
  Future<Json> review(String id) => _c.put('/product-requests/$id/review');
  Future<Json> approve(String id, Json body) => _c.put('/product-requests/$id/approve', body: body);
  Future<Json> reject(String id, String reason) => _c.put('/product-requests/$id/reject', body: {'reason': reason});
  Future<Json> cancel(String id, String? reason) => _c.put('/product-requests/$id/cancel', body: {if (reason != null) 'reason': reason});
}

class PackingApi {
  PackingApi(this._c);
  final ApiClient _c;
  Future<Json> list(Map<String, dynamic> q) => _c.get('/packing-orders', query: q);
  Future<Json> get(String id) => _c.get('/packing-orders/$id');
  Future<Json> create(Json body) => _c.post('/packing-orders', body: body);
  Future<Json> fromRequests(Json body) => _c.post('/packing-orders/from-requests', body: body);
  Future<Json> update(String id, Json body) => _c.put('/packing-orders/$id', body: body);
  Future<Json> action(String id, String action, [Json? body]) => _c.put('/packing-orders/$id/$action', body: body);
}

class TransferApi {
  TransferApi(this._c);
  final ApiClient _c;
  Future<Json> list(Map<String, dynamic> q) => _c.get('/transfers', query: q);
  Future<Json> get(String id) => _c.get('/transfers/$id');
  Future<Json> create(Json body) => _c.post('/transfers', body: body);
  Future<Json> action(String id, String action, [Json? body]) => _c.put('/transfers/$id/$action', body: body);
}

class SalesApi {
  SalesApi(this._c);
  final ApiClient _c;
  Future<Json> list(Map<String, dynamic> q) => _c.get('/sales', query: q);
  Future<Json> get(String id) => _c.get('/sales/$id');
  Future<Json> create(Json body) => _c.post('/sales', body: body);
  Future<Json> cancel(String id, String reason) => _c.put('/sales/$id/cancel', body: {'reason': reason});
  Future<Json> returns(Map<String, dynamic> q) => _c.get('/returns', query: q);
  Future<Json> getReturn(String id) => _c.get('/returns/$id');
  Future<Json> createReturn(Json body) => _c.post('/returns', body: body);
}

class PlatformApi {
  PlatformApi(this._c);
  final ApiClient _c;
  Future<Json> dashboard(Map<String, dynamic> q) => _c.get('/dashboard', query: q);
  Future<Json> notifications(Map<String, dynamic> q) => _c.get('/notifications', query: q);
  Future<Json> unreadCount() => _c.get('/notifications/unread-count');
  Future<Json> markRead(String id) => _c.put('/notifications/$id/read');
  Future<Json> markAllRead() => _c.put('/notifications/read-all');
  Future<Json> settings() => _c.get('/settings');
  Future<Json> updateSettings(Json body) => _c.put('/settings', body: body);
  Future<Json> auditLogs(Map<String, dynamic> q) => _c.get('/audit-logs', query: q);
  Future<Json> auditFacets() => _c.get('/audit-logs/facets');
  Future<DownloadedFile> exportAudit(Map<String, dynamic> q) => _c.download('/audit-logs/export', query: q, fallbackName: 'audit-log.csv');
  Future<Json> report(String kind, Map<String, dynamic> q) => _c.get('/reports/$kind', query: q);
  Future<DownloadedFile> exportReport(String kind, Map<String, dynamic> q) => _c.download('/reports/$kind', query: q, fallbackName: 'report');
}
