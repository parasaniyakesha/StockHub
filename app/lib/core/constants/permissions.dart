/// Permission keys - mirror of server/src/config/permissions.ts.
/// The UI uses them only to show/hide features; the API enforces them.
class Perm {
  Perm._();

  static const productsManage = 'products.manage';
  static const categoriesManage = 'categories.manage';
  static const storesManage = 'stores.manage';
  static const usersManage = 'users.manage';
  static const stockView = 'stock.view';
  static const stockAdjust = 'stock.adjust';
  static const stockDamage = 'stock.damage';
  static const warehouseManage = 'warehouse.manage';
  static const requestsCreate = 'requests.create';
  static const requestsApprove = 'requests.approve';
  static const packingManage = 'packing.manage';
  static const packingReceive = 'packing.receive';
  static const transfersRequest = 'transfers.request';
  static const transfersApprove = 'transfers.approve';
  static const transfersDispatch = 'transfers.dispatch';
  static const transfersReceive = 'transfers.receive';
  static const salesView = 'sales.view';
  static const salesCreate = 'sales.create';
  static const salesCancel = 'sales.cancel';
  static const returnsManage = 'returns.manage';
  static const availabilitySubmit = 'availability.submit';
  static const reportsView = 'reports.view';
  static const auditView = 'audit.view';
  static const settingsManage = 'settings.manage';

  /// Human readable labels for the manager permission editor.
  static const Map<String, String> labels = {
    stockView: 'View stock',
    stockAdjust: 'Adjust stock',
    stockDamage: 'Report damaged stock',
    requestsApprove: 'Approve product requests',
    packingReceive: 'Receive packing orders',
    transfersRequest: 'Request transfers',
    transfersApprove: 'Approve transfers',
    transfersDispatch: 'Dispatch transfers',
    transfersReceive: 'Receive transfers',
    salesView: 'View sales',
    salesCreate: 'Record sales',
    salesCancel: 'Cancel sales',
    returnsManage: 'Manage returns',
    reportsView: 'View reports',
    usersManage: 'Manage store users',
  };
}

class Roles {
  Roles._();
  static const admin = 'ADMIN';
  static const manager = 'MANAGER';
  static const store = 'STORE';
}
