/// Route names. Static routes are registered before parameterised ones so
/// `/sales/new` is never captured by `/sales/:id`.
class AppRoutes {
  AppRoutes._();

  static const splash = '/';
  static const login = '/login';
  static const forgotPassword = '/forgot-password';

  static const dashboard = '/dashboard';

  static const products = '/products';
  static const productDetail = '/products/:id';
  static String product(String id) => '/products/$id';

  static const categories = '/categories';

  static const stores = '/stores';
  static const storeDetail = '/stores/:id';
  static String store(String id) => '/stores/$id';

  static const stock = '/stock';
  static const stockMovements = '/stock/movements';
  static const stockAvailability = '/stock/availability';

  static const requests = '/product-requests';
  static const requestNew = '/product-requests/new';
  static const requestDetail = '/product-requests/:id';
  static const requestEdit = '/product-requests/:id/edit';
  static String request(String id) => '/product-requests/$id';
  static String editRequest(String id) => '/product-requests/$id/edit';

  static const packingOrders = '/packing-orders';
  static const packingNew = '/packing-orders/new';
  static const packingDetail = '/packing-orders/:id';
  static const packingEdit = '/packing-orders/:id/edit';
  static String packingOrder(String id) => '/packing-orders/$id';
  static String editPackingOrder(String id) => '/packing-orders/$id/edit';

  static const transfers = '/transfers';
  static const transferNew = '/transfers/new';
  static const transferDetail = '/transfers/:id';
  static String transfer(String id) => '/transfers/$id';

  static const sales = '/sales';
  static const saleNew = '/sales/new';
  static const saleDetail = '/sales/:id';
  static String sale(String id) => '/sales/$id';

  static const returns = '/returns';
  static const returnNew = '/returns/new';
  static const returnDetail = '/returns/:id';
  static String saleReturn(String id) => '/returns/$id';

  static const reports = '/reports';
  static const users = '/users';
  static const managers = '/managers';
  static const notifications = '/notifications';
  static const settings = '/settings';
  static const auditLogs = '/audit-logs';
}
