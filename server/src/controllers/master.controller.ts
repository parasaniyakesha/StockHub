import { Request, Response } from 'express';
import { ctx } from '../middleware/authorize';
import { created, ok, paginated } from '../utils/response';
import { toNumber } from '../utils/money';
import * as users from '../services/user.service';
import * as stores from '../services/store.service';
import * as categories from '../services/category.service';
import * as products from '../services/product.service';
import * as warehouses from '../services/warehouse.service';
import { sendExport } from '../services/export.service';

const v = (req: Request) => req.validated!;

// ─────────────── Users & managers ───────────────

export const userController = {
  async list(req: Request, res: Response) {
    const q = v(req).query;
    const { rows, total } = await users.listUsers(ctx(req), q);
    paginated(res, rows, { page: q.page, limit: q.limit, total }, 'Users retrieved successfully');
  },
  async get(req: Request, res: Response) {
    ok(res, await users.getUser(ctx(req), v(req).params.id), 'User retrieved');
  },
  async create(req: Request, res: Response) {
    created(res, await users.createUser(ctx(req), v(req).body), 'User created');
  },
  async update(req: Request, res: Response) {
    ok(res, await users.updateUser(ctx(req), v(req).params.id, v(req).body), 'User updated');
  },
  async setStatus(req: Request, res: Response) {
    ok(res, await users.updateUser(ctx(req), v(req).params.id, { status: v(req).body.status }), 'User status updated');
  },
  async resetPassword(req: Request, res: Response) {
    await users.adminResetPassword(ctx(req), v(req).params.id, v(req).body.newPassword);
    ok(res, null, 'Password reset. The user must sign in again.');
  },
  async remove(req: Request, res: Response) {
    const result = await users.deleteUser(ctx(req), v(req).params.id);
    ok(res, result, result.deleted ? 'User deleted' : 'User has activity history and was deactivated instead');
  },
};

export const managerController = {
  async list(req: Request, res: Response) {
    const q = v(req).query;
    const { rows, total } = await users.listManagers(q);
    paginated(res, rows, { page: q.page, limit: q.limit, total }, 'Managers retrieved successfully');
  },
  async setStores(req: Request, res: Response) {
    ok(res, await users.setManagerStores(ctx(req), v(req).params.id, v(req).body.storeIds), 'Manager stores updated');
  },
  async setPermissions(req: Request, res: Response) {
    ok(res, await users.setManagerPermissions(ctx(req), v(req).params.id, v(req).body.permissions), 'Manager permissions updated');
  },
};

// ─────────────── Stores ───────────────

export const storeController = {
  async list(req: Request, res: Response) {
    const q = v(req).query;
    const { rows, total } = await stores.listStores(ctx(req), q);
    paginated(res, rows, { page: q.page, limit: q.limit, total }, 'Stores retrieved successfully');
  },
  async get(req: Request, res: Response) {
    ok(res, await stores.getStore(ctx(req), v(req).params.id), 'Store retrieved');
  },
  async create(req: Request, res: Response) {
    created(res, await stores.createStore(ctx(req), v(req).body), 'Store created');
  },
  async update(req: Request, res: Response) {
    ok(res, await stores.updateStore(ctx(req), v(req).params.id, v(req).body), 'Store updated');
  },
  async setStatus(req: Request, res: Response) {
    ok(res, await stores.setStoreStatus(ctx(req), v(req).params.id, v(req).body.status), 'Store status updated');
  },
  async assignManager(req: Request, res: Response) {
    ok(res, await stores.assignManager(ctx(req), v(req).params.id, v(req).body.managerId), 'Manager assigned');
  },
  async assignUsers(req: Request, res: Response) {
    ok(res, await stores.assignStoreUsers(ctx(req), v(req).params.id, v(req).body.userIds), 'Users assigned');
  },
  async remove(req: Request, res: Response) {
    const result = await stores.deleteStore(ctx(req), v(req).params.id);
    ok(res, result, result.deleted ? 'Store deleted' : 'Store has related records and was deactivated instead');
  },
};

// ─────────────── Categories ───────────────

export const categoryController = {
  async list(req: Request, res: Response) {
    const q = v(req).query;
    const { rows, total } = await categories.listCategories(ctx(req), q);
    paginated(res, rows, { page: q.all ? 1 : q.page, limit: q.all ? total : q.limit, total }, 'Categories retrieved successfully');
  },
  async get(req: Request, res: Response) {
    ok(res, await categories.getCategory(v(req).params.id), 'Category retrieved');
  },
  async create(req: Request, res: Response) {
    created(res, await categories.createCategory(ctx(req), v(req).body), 'Category created');
  },
  async update(req: Request, res: Response) {
    ok(res, await categories.updateCategory(ctx(req), v(req).params.id, v(req).body), 'Category updated');
  },
  async setStatus(req: Request, res: Response) {
    ok(res, await categories.setCategoryStatus(ctx(req), v(req).params.id, v(req).body.status), 'Category status updated');
  },
  async assignProducts(req: Request, res: Response) {
    ok(res, await categories.assignProducts(ctx(req), v(req).params.id, v(req).body.productIds), 'Products assigned');
  },
};

// ─────────────── Products ───────────────

export const productController = {
  async list(req: Request, res: Response) {
    const q = v(req).query;
    const { rows, total } = await products.listProducts(ctx(req), q);
    paginated(res, rows, { page: q.page, limit: q.limit, total }, 'Products retrieved successfully');
  },
  async export(req: Request, res: Response) {
    const context = ctx(req);
    const rows = await products.exportProducts(context, v(req).query);
    const store = context.user.role === 'STORE';
    await sendExport(res, req.query.format as 'csv' | 'xlsx' | 'pdf', 'products', 'Products', [
      { header: 'SKU', value: (r) => r.sku, width: 12 },
      { header: 'Name', value: (r) => r.name, width: 28 },
      { header: 'Barcode', value: (r) => r.barcode, width: 16 },
      { header: 'Category', value: (r) => r.category.name, width: 16 },
      { header: 'Brand', value: (r) => r.brand, width: 14 },
      { header: 'Unit', value: (r) => r.unit, width: 8 },
      ...(store ? [] : [{ header: 'Purchase price', value: (r: (typeof rows)[number]) => toNumber(r.purchasePrice).toFixed(2), numeric: true, width: 12 }]),
      { header: 'Selling price', value: (r) => toNumber(r.sellingPrice).toFixed(2), numeric: true, width: 12 },
      { header: 'Tax %', value: (r) => toNumber(r.taxRate), numeric: true, width: 8 },
      { header: 'Min stock', value: (r) => r.minimumStock, numeric: true, width: 10 },
      ...(store ? [] : [{ header: 'Warehouse qty', value: (r: (typeof rows)[number]) => r.warehouseQuantity, numeric: true, width: 12 }]),
      { header: 'Store qty', value: (r) => r.storeQuantity, numeric: true, width: 10 },
      { header: 'Status', value: (r) => r.status, width: 10 },
    ], rows);
  },
  async get(req: Request, res: Response) {
    ok(res, await products.getProduct(ctx(req), v(req).params.id), 'Product retrieved');
  },
  async create(req: Request, res: Response) {
    created(res, await products.createProduct(ctx(req), v(req).body), 'Product created');
  },
  async update(req: Request, res: Response) {
    ok(res, await products.updateProduct(ctx(req), v(req).params.id, v(req).body), 'Product updated');
  },
  async setStatus(req: Request, res: Response) {
    ok(res, await products.setProductStatus(ctx(req), v(req).params.id, v(req).body.status), 'Product status updated');
  },
  async remove(req: Request, res: Response) {
    const result = await products.deleteProduct(ctx(req), v(req).params.id);
    ok(res, result, result.deleted ? 'Product deleted' : 'Product has stock history and was deactivated instead');
  },
  async import(req: Request, res: Response) {
    const result = await products.importProducts(ctx(req), v(req).body.rows);
    // Always 200: the body carries per-row errors for the client to display.
    // Nothing is written when any row is invalid.
    ok(res, result, result.errors.length ? 'Import failed - fix the listed rows and try again' : 'Import completed');
  },
};

// ─────────────── Warehouses ───────────────

export const warehouseController = {
  async list(_req: Request, res: Response) {
    ok(res, await warehouses.listWarehouses(), 'Warehouses retrieved');
  },
  async create(req: Request, res: Response) {
    created(res, await warehouses.createWarehouse(ctx(req), v(req).body), 'Warehouse created');
  },
  async update(req: Request, res: Response) {
    ok(res, await warehouses.updateWarehouse(ctx(req), v(req).params.id, v(req).body), 'Warehouse updated');
  },
};
