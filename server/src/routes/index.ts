import { Router } from 'express';
import { z } from 'zod';
import { Role } from '@prisma/client';
import { authenticate } from '../middleware/authenticate';
import { requirePermission, requireRole } from '../middleware/authorize';
import { validate } from '../middleware/validate';
import { authLimiter } from '../middleware/rateLimit';
import { PERMISSIONS as P } from '../config/permissions';
import { prisma } from '../utils/prisma';

import * as auth from '../controllers/auth.controller';
import { categoryController, managerController, productController, storeController, userController, warehouseController } from '../controllers/master.controller';
import { packingController, requestController, returnController, saleController, stockController, transferController } from '../controllers/operations.controller';
import { auditController, dashboardController, notificationController, reportController, settingsController } from '../controllers/platform.controller';

import { idParam, listQuery, statusBody } from '../validators/common.validator';
import { changePasswordSchema, forgotPasswordSchema, loginSchema, logoutSchema, refreshSchema, resetPasswordSchema, updateProfileSchema } from '../validators/auth.validator';
import { adminResetPasswordSchema, createUserSchema, managerPermissionsSchema, managerStoresSchema, updateUserSchema, userListQuery } from '../validators/user.validator';
import {
  assignManagerSchema, assignProductsSchema, assignStoreUsersSchema, categoryListQuery, createCategorySchema, createProductSchema,
  createStoreSchema, exportQuery, importProductsSchema, productListQuery, storeListQuery, updateCategorySchema, updateProductSchema,
  updateStoreSchema, warehouseSchema,
} from '../validators/catalog.validator';
import { adjustmentSchema, availabilitySchema, damageSchema, deleteBalanceQuery, movementListQuery, openingStockSchema, purchaseSchema, stockListQuery, writeOffSchema } from '../validators/stock.validator';
import {
  approveRequestSchema, approveTransferSchema, createPackingOrderSchema, createRequestSchema, createReturnSchema, createSaleSchema,
  createTransferSchema, optionalReasonSchema, packingFromRequestsSchema, packSchema, reasonSchema, receiveLinesSchema, returnListQuery,
  saleListQuery, transferListQuery, updatePackingOrderSchema, updateRequestSchema,
} from '../validators/operations.validator';
import { dashboardQuery, notificationListQuery, updateSettingsSchema } from '../validators/settings.validator';
import { reportQuery } from '../services/report.service';
import { auditListQuery } from '../services/auditLog.service';

const router = Router();
const byId = { params: idParam };
const empty = z.object({}).strict();

// ─────────────── Health ───────────────
router.get('/health', async (_req, res) => {
  await prisma.$runCommandRaw({ ping: 1 });
  res.json({ success: true, message: 'OK', data: { status: 'ok', time: new Date().toISOString() } });
});

// ─────────────── Auth (public) ───────────────
router.post('/auth/login', authLimiter, validate({ body: loginSchema }), auth.login);
router.post('/auth/refresh', authLimiter, validate({ body: refreshSchema }), auth.refresh);
router.post('/auth/forgot-password', authLimiter, validate({ body: forgotPasswordSchema }), auth.forgotPassword);
router.post('/auth/reset-password', authLimiter, validate({ body: resetPasswordSchema }), auth.resetPassword);

// Everything below requires a valid access token.
router.use(authenticate);

router.post('/auth/logout', validate({ body: logoutSchema }), auth.logout);
router.get('/auth/me', auth.me);
router.put('/auth/me', validate({ body: updateProfileSchema }), auth.updateProfile);
router.put('/auth/change-password', validate({ body: changePasswordSchema }), auth.changePassword);

// ─────────────── Dashboard & notifications ───────────────
router.get('/dashboard', validate({ query: dashboardQuery }), dashboardController.get);

router.get('/notifications', validate({ query: notificationListQuery }), notificationController.list);
router.get('/notifications/unread-count', notificationController.unreadCount);
router.put('/notifications/read-all', notificationController.markAllRead);
router.put('/notifications/:id/read', validate(byId), notificationController.markRead);

// ─────────────── Users & managers ───────────────
router.get('/users', requirePermission(P.USERS_MANAGE), validate({ query: userListQuery }), userController.list);
router.post('/users', requirePermission(P.USERS_MANAGE), validate({ body: createUserSchema }), userController.create);
router.get('/users/:id', requirePermission(P.USERS_MANAGE), validate(byId), userController.get);
router.put('/users/:id', requirePermission(P.USERS_MANAGE), validate({ ...byId, body: updateUserSchema }), userController.update);
router.patch('/users/:id/status', requirePermission(P.USERS_MANAGE), validate({ ...byId, body: statusBody }), userController.setStatus);
router.put('/users/:id/password', requirePermission(P.USERS_MANAGE), validate({ ...byId, body: adminResetPasswordSchema }), userController.resetPassword);
router.delete('/users/:id', requirePermission(P.USERS_MANAGE), validate(byId), userController.remove);

router.get('/managers', requireRole(Role.ADMIN), validate({ query: userListQuery }), managerController.list);
router.put('/managers/:id/stores', requireRole(Role.ADMIN), validate({ ...byId, body: managerStoresSchema }), managerController.setStores);
router.put('/managers/:id/permissions', requireRole(Role.ADMIN), validate({ ...byId, body: managerPermissionsSchema }), managerController.setPermissions);

// ─────────────── Stores ───────────────
router.get('/stores', validate({ query: storeListQuery }), storeController.list);
router.post('/stores', requirePermission(P.STORES_MANAGE), validate({ body: createStoreSchema }), storeController.create);
router.get('/stores/:id', validate(byId), storeController.get);
router.put('/stores/:id', requirePermission(P.STORES_MANAGE), validate({ ...byId, body: updateStoreSchema }), storeController.update);
router.patch('/stores/:id/status', requirePermission(P.STORES_MANAGE), validate({ ...byId, body: statusBody }), storeController.setStatus);
router.put('/stores/:id/manager', requirePermission(P.STORES_MANAGE), validate({ ...byId, body: assignManagerSchema }), storeController.assignManager);
router.put('/stores/:id/users', requirePermission(P.STORES_MANAGE), validate({ ...byId, body: assignStoreUsersSchema }), storeController.assignUsers);
router.delete('/stores/:id', requirePermission(P.STORES_MANAGE), validate(byId), storeController.remove);

// ─────────────── Warehouses ───────────────
router.get('/warehouses', requireRole(Role.ADMIN, Role.MANAGER), warehouseController.list);
router.post('/warehouses', requirePermission(P.WAREHOUSE_MANAGE), validate({ body: warehouseSchema }), warehouseController.create);
router.put('/warehouses/:id', requirePermission(P.WAREHOUSE_MANAGE), validate({ ...byId, body: warehouseSchema.partial() }), warehouseController.update);

// ─────────────── Categories ───────────────
router.get('/categories', validate({ query: categoryListQuery }), categoryController.list);
router.post('/categories', requirePermission(P.CATEGORIES_MANAGE), validate({ body: createCategorySchema }), categoryController.create);
router.get('/categories/:id', validate(byId), categoryController.get);
router.put('/categories/:id', requirePermission(P.CATEGORIES_MANAGE), validate({ ...byId, body: updateCategorySchema }), categoryController.update);
router.patch('/categories/:id/status', requirePermission(P.CATEGORIES_MANAGE), validate({ ...byId, body: statusBody }), categoryController.setStatus);
router.put('/categories/:id/products', requirePermission(P.CATEGORIES_MANAGE), validate({ ...byId, body: assignProductsSchema }), categoryController.assignProducts);

// ─────────────── Products ───────────────
router.get('/products', validate({ query: productListQuery }), productController.list);
router.get('/products/export', validate({ query: productListQuery.extend(exportQuery.shape) }), productController.export);
router.post('/products/import', requirePermission(P.PRODUCTS_MANAGE), validate({ body: importProductsSchema }), productController.import);
router.post('/products', requirePermission(P.PRODUCTS_MANAGE), validate({ body: createProductSchema }), productController.create);
router.get('/products/:id', validate(byId), productController.get);
router.put('/products/:id', requirePermission(P.PRODUCTS_MANAGE), validate({ ...byId, body: updateProductSchema }), productController.update);
router.patch('/products/:id/status', requirePermission(P.PRODUCTS_MANAGE), validate({ ...byId, body: statusBody }), productController.setStatus);
router.delete('/products/:id', requirePermission(P.PRODUCTS_MANAGE), validate(byId), productController.remove);

// ─────────────── Stock ───────────────
router.get('/stock', requirePermission(P.STOCK_VIEW), validate({ query: stockListQuery }), stockController.list);
router.get('/stock/movements', requirePermission(P.STOCK_VIEW), validate({ query: movementListQuery }), stockController.movements);
router.get('/stock/movements/export', requirePermission(P.STOCK_VIEW), validate({ query: movementListQuery.extend(exportQuery.shape) }), stockController.exportMovements);
router.post('/stock/opening', requireRole(Role.ADMIN), validate({ body: openingStockSchema }), stockController.opening);
router.post('/stock/purchases', requirePermission(P.WAREHOUSE_MANAGE), validate({ body: purchaseSchema }), stockController.purchase);
router.post('/stock/adjustments', requirePermission(P.STOCK_ADJUST), validate({ body: adjustmentSchema }), stockController.adjust);
router.post('/stock/damage', requirePermission(P.STOCK_DAMAGE), validate({ body: damageSchema }), stockController.damage);
router.post('/stock/damage/write-off', requirePermission(P.STOCK_ADJUST), validate({ body: writeOffSchema }), stockController.writeOff);
router.post('/stock/availability', requirePermission(P.AVAILABILITY_SUBMIT), validate({ body: availabilitySchema }), stockController.submitAvailability);
router.get('/stock/availability', requirePermission(P.STOCK_VIEW), validate({ query: stockListQuery }), stockController.availability);
router.get('/stock/availability/matrix', requireRole(Role.ADMIN, Role.MANAGER), validate({ query: stockListQuery }), stockController.availabilityMatrix);
router.delete('/stock/:id', requirePermission(P.STOCK_ADJUST), validate({ ...byId, query: deleteBalanceQuery }), stockController.deleteBalance);

// ─────────────── Product requests ───────────────
router.get('/product-requests', validate({ query: listQuery }), requestController.list);
router.post('/product-requests', requirePermission(P.REQUESTS_CREATE), validate({ body: createRequestSchema }), requestController.create);
router.get('/product-requests/:id', validate(byId), requestController.get);
router.put('/product-requests/:id', requirePermission(P.REQUESTS_CREATE), validate({ ...byId, body: updateRequestSchema }), requestController.update);
router.put('/product-requests/:id/submit', requirePermission(P.REQUESTS_CREATE), validate(byId), requestController.submit);
router.put('/product-requests/:id/review', requirePermission(P.REQUESTS_APPROVE), validate(byId), requestController.review);
router.put('/product-requests/:id/approve', requirePermission(P.REQUESTS_APPROVE), validate({ ...byId, body: approveRequestSchema }), requestController.approve);
router.put('/product-requests/:id/reject', requirePermission(P.REQUESTS_APPROVE), validate({ ...byId, body: reasonSchema }), requestController.reject);
router.put('/product-requests/:id/cancel', requirePermission(P.REQUESTS_CREATE, P.REQUESTS_APPROVE), validate({ ...byId, body: optionalReasonSchema }), requestController.cancel);

// ─────────────── Packing orders ───────────────
router.get('/packing-orders', validate({ query: listQuery }), packingController.list);
router.post('/packing-orders', requirePermission(P.PACKING_MANAGE), validate({ body: createPackingOrderSchema }), packingController.create);
router.post('/packing-orders/from-requests', requirePermission(P.PACKING_MANAGE), validate({ body: packingFromRequestsSchema }), packingController.fromRequests);
router.get('/packing-orders/:id', validate(byId), packingController.get);
router.put('/packing-orders/:id', requirePermission(P.PACKING_MANAGE), validate({ ...byId, body: updatePackingOrderSchema }), packingController.update);
router.put('/packing-orders/:id/assign', requirePermission(P.PACKING_MANAGE), validate(byId), packingController.assign);
router.put('/packing-orders/:id/start-packing', requirePermission(P.PACKING_MANAGE), validate(byId), packingController.startPacking);
router.put('/packing-orders/:id/pack', requirePermission(P.PACKING_MANAGE), validate({ ...byId, body: packSchema }), packingController.pack);
router.put('/packing-orders/:id/dispatch', requirePermission(P.PACKING_MANAGE), validate(byId), packingController.dispatch);
router.put('/packing-orders/:id/receive', requirePermission(P.PACKING_RECEIVE), validate({ ...byId, body: receiveLinesSchema }), packingController.receive);
router.put('/packing-orders/:id/complete', requirePermission(P.PACKING_MANAGE), validate(byId), packingController.complete);
router.put('/packing-orders/:id/cancel', requirePermission(P.PACKING_MANAGE), validate({ ...byId, body: reasonSchema }), packingController.cancel);

// ─────────────── Transfers ───────────────
router.get('/transfers', validate({ query: transferListQuery }), transferController.list);
router.post('/transfers', requirePermission(P.TRANSFERS_REQUEST), validate({ body: createTransferSchema }), transferController.create);
router.get('/transfers/:id', validate(byId), transferController.get);
router.put('/transfers/:id/approve', requirePermission(P.TRANSFERS_APPROVE), validate({ ...byId, body: approveTransferSchema }), transferController.approve);
router.put('/transfers/:id/reject', requirePermission(P.TRANSFERS_APPROVE), validate({ ...byId, body: reasonSchema }), transferController.reject);
router.put('/transfers/:id/dispatch', requirePermission(P.TRANSFERS_DISPATCH), validate(byId), transferController.dispatch);
router.put('/transfers/:id/receive', requirePermission(P.TRANSFERS_RECEIVE), validate({ ...byId, body: receiveLinesSchema }), transferController.receive);
router.put('/transfers/:id/complete', requirePermission(P.TRANSFERS_APPROVE, P.TRANSFERS_RECEIVE), validate(byId), transferController.complete);
router.put('/transfers/:id/cancel', requirePermission(P.TRANSFERS_REQUEST, P.TRANSFERS_APPROVE), validate({ ...byId, body: optionalReasonSchema }), transferController.cancel);

// ─────────────── Sales & returns ───────────────
router.get('/sales', requirePermission(P.SALES_VIEW), validate({ query: saleListQuery }), saleController.list);
router.post('/sales', requirePermission(P.SALES_CREATE), validate({ body: createSaleSchema }), saleController.create);
router.get('/sales/:id', requirePermission(P.SALES_VIEW), validate(byId), saleController.get);
router.put('/sales/:id/cancel', requirePermission(P.SALES_CANCEL), validate({ ...byId, body: reasonSchema }), saleController.cancel);

router.get('/returns', requirePermission(P.SALES_VIEW, P.RETURNS_MANAGE), validate({ query: returnListQuery }), returnController.list);
router.post('/returns', requirePermission(P.RETURNS_MANAGE), validate({ body: createReturnSchema }), returnController.create);
router.get('/returns/:id', requirePermission(P.SALES_VIEW, P.RETURNS_MANAGE), validate(byId), returnController.get);

// ─────────────── Reports ───────────────
router.get('/reports/stock', requirePermission(P.REPORTS_VIEW), validate({ query: reportQuery }), reportController.stock);
router.get('/reports/sales', requirePermission(P.REPORTS_VIEW), validate({ query: reportQuery }), reportController.sales);
router.get('/reports/operations', requirePermission(P.REPORTS_VIEW), validate({ query: reportQuery }), reportController.operations);
router.get('/reports/stores', requirePermission(P.REPORTS_VIEW), validate({ query: reportQuery }), reportController.stores);

// ─────────────── Settings & audit ───────────────
router.get('/settings', settingsController.get);
router.put('/settings', requirePermission(P.SETTINGS_MANAGE), validate({ body: updateSettingsSchema }), settingsController.update);
router.get('/settings/permissions', requireRole(Role.ADMIN), validate({ query: empty }), settingsController.permissions);

router.get('/audit-logs', requirePermission(P.AUDIT_VIEW), validate({ query: auditListQuery }), auditController.list);
router.get('/audit-logs/facets', requirePermission(P.AUDIT_VIEW), auditController.facets);
router.get('/audit-logs/export', requirePermission(P.AUDIT_VIEW), validate({ query: auditListQuery.extend({ format: z.enum(['csv', 'xlsx', 'pdf']).default('csv') }) }), auditController.export);

export default router;
