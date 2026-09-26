import { Role } from '@prisma/client';

/**
 * Permission keys. ADMIN implicitly holds every permission. STORE users have a
 * fixed set. MANAGER permissions are configurable per manager by an admin
 * (stored in users.permissions) - always limited to the manager's assigned stores.
 */
export const PERMISSIONS = {
  PRODUCTS_MANAGE: 'products.manage',
  CATEGORIES_MANAGE: 'categories.manage',
  STORES_MANAGE: 'stores.manage',
  USERS_MANAGE: 'users.manage',
  STOCK_VIEW: 'stock.view',
  STOCK_ADJUST: 'stock.adjust',
  STOCK_DAMAGE: 'stock.damage',
  WAREHOUSE_MANAGE: 'warehouse.manage',
  REQUESTS_CREATE: 'requests.create',
  REQUESTS_APPROVE: 'requests.approve',
  PACKING_MANAGE: 'packing.manage',
  PACKING_RECEIVE: 'packing.receive',
  TRANSFERS_REQUEST: 'transfers.request',
  TRANSFERS_APPROVE: 'transfers.approve',
  TRANSFERS_DISPATCH: 'transfers.dispatch',
  TRANSFERS_RECEIVE: 'transfers.receive',
  SALES_VIEW: 'sales.view',
  SALES_CREATE: 'sales.create',
  SALES_CANCEL: 'sales.cancel',
  RETURNS_MANAGE: 'returns.manage',
  AVAILABILITY_SUBMIT: 'availability.submit',
  REPORTS_VIEW: 'reports.view',
  AUDIT_VIEW: 'audit.view',
  SETTINGS_MANAGE: 'settings.manage',
} as const;

export type Permission = (typeof PERMISSIONS)[keyof typeof PERMISSIONS];

export const ALL_PERMISSIONS: Permission[] = Object.values(PERMISSIONS);

/** Permissions an admin may grant to a manager. */
export const MANAGER_ASSIGNABLE_PERMISSIONS: Permission[] = [
  PERMISSIONS.STOCK_VIEW,
  PERMISSIONS.STOCK_ADJUST,
  PERMISSIONS.STOCK_DAMAGE,
  PERMISSIONS.REQUESTS_APPROVE,
  PERMISSIONS.PACKING_RECEIVE,
  PERMISSIONS.TRANSFERS_REQUEST,
  PERMISSIONS.TRANSFERS_APPROVE,
  PERMISSIONS.TRANSFERS_DISPATCH,
  PERMISSIONS.TRANSFERS_RECEIVE,
  PERMISSIONS.SALES_VIEW,
  PERMISSIONS.SALES_CREATE,
  PERMISSIONS.SALES_CANCEL,
  PERMISSIONS.RETURNS_MANAGE,
  PERMISSIONS.REPORTS_VIEW,
  PERMISSIONS.USERS_MANAGE,
];

export const DEFAULT_MANAGER_PERMISSIONS: Permission[] = [
  PERMISSIONS.STOCK_VIEW,
  PERMISSIONS.STOCK_DAMAGE,
  PERMISSIONS.REQUESTS_APPROVE,
  PERMISSIONS.TRANSFERS_REQUEST,
  PERMISSIONS.TRANSFERS_APPROVE,
  PERMISSIONS.TRANSFERS_DISPATCH,
  PERMISSIONS.TRANSFERS_RECEIVE,
  PERMISSIONS.SALES_VIEW,
  PERMISSIONS.RETURNS_MANAGE,
  PERMISSIONS.REPORTS_VIEW,
];

export const STORE_PERMISSIONS: Permission[] = [
  PERMISSIONS.STOCK_VIEW,
  PERMISSIONS.STOCK_DAMAGE,
  PERMISSIONS.REQUESTS_CREATE,
  PERMISSIONS.PACKING_RECEIVE,
  PERMISSIONS.TRANSFERS_REQUEST,
  PERMISSIONS.TRANSFERS_DISPATCH,
  PERMISSIONS.TRANSFERS_RECEIVE,
  PERMISSIONS.SALES_VIEW,
  PERMISSIONS.SALES_CREATE,
  PERMISSIONS.RETURNS_MANAGE,
  PERMISSIONS.AVAILABILITY_SUBMIT,
  PERMISSIONS.REPORTS_VIEW,
];

export function effectivePermissions(role: Role, managerPermissions: string[] = []): Permission[] {
  switch (role) {
    case Role.ADMIN:
      return ALL_PERMISSIONS;
    case Role.STORE:
      return STORE_PERMISSIONS;
    case Role.MANAGER:
      return managerPermissions.filter((p): p is Permission =>
        MANAGER_ASSIGNABLE_PERMISSIONS.includes(p as Permission),
      );
    default:
      return [];
  }
}
