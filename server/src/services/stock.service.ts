import { MovementType, Prisma, RecordStatus, Role, StockBucket } from '@prisma/client';
import { z } from 'zod';
import { prisma, transaction } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { contains, dateRange, orderBy, pageArgs } from '../utils/pagination';
import { assertStoreAccess, storeFilter } from '../middleware/storeScope';
import { RequestContext } from '../types/auth';
import { applyMovement, moveToDamaged, ReferenceType, StockLocation } from './stockLedger.service';
import { audit } from './audit.service';
import { notify, NotificationType } from './notification.service';
import { categoryWithDescendants } from './category.service';
import { resolveWarehouse } from './warehouse.service';
import {
  adjustmentSchema,
  availabilitySchema,
  damageSchema,
  movementListQuery,
  openingStockSchema,
  purchaseSchema,
  stockListQuery,
  writeOffSchema,
} from '../validators/stock.validator';

type StockListQuery = z.infer<typeof stockListQuery>;
type MovementListQuery = z.infer<typeof movementListQuery>;

const productSelect = {
  id: true,
  name: true,
  sku: true,
  unit: true,
  minimumStock: true,
  maximumStock: true,
  sellingPrice: true,
  purchasePrice: true,
  category: { select: { id: true, name: true } },
} as const;

async function productWhere(q: StockListQuery): Promise<Prisma.ProductWhereInput> {
  const search = contains(q.search);
  return {
    ...(search ? { OR: [{ name: search }, { sku: search }, { barcode: search }] } : {}),
    ...(q.categoryId ? { categoryId: { in: await categoryWithDescendants(q.categoryId) } } : {}),
  };
}

const balanceSort = (q: StockListQuery) =>
  orderBy(q, {
    product: (d) => ({ product: { name: d } }),
    sku: (d) => ({ product: { sku: d } }),
    quantity: (d) => ({ quantity: d }),
    damaged: (d) => ({ damagedQuantity: d }),
    updatedAt: (d) => ({ updatedAt: d }),
  }, { product: { name: 'asc' } });

/** Current balances for the warehouse or for stores (scoped). */
export async function listStock(context: RequestContext, q: StockListQuery): Promise<{ rows: object[]; total: number }> {
  const pWhere = await productWhere(q);

  if (q.locationType === 'WAREHOUSE') {
    if (context.user.role === Role.STORE) throw ApiError.forbidden();
    const where: Prisma.WarehouseStockWhereInput = {
      ...(q.warehouseId ? { warehouseId: q.warehouseId } : {}),
      product: pWhere,
      ...(q.hideZero ? { OR: [{ quantity: { not: 0 } }, { damagedQuantity: { not: 0 } }] } : {}),
    };
    if (q.lowStock) {
      const ws = await prisma.warehouseStock.findMany({
        where: q.warehouseId ? { warehouseId: q.warehouseId } : {},
        select: { id: true, quantity: true, product: { select: { minimumStock: true } } },
      });
      const ids = ws.filter((w) => w.quantity <= w.product.minimumStock).map((w) => w.id);
      where.id = { in: ids };
    }
    const [rows, total] = await Promise.all([
      prisma.warehouseStock.findMany({
        where,
        include: { product: { select: productSelect }, warehouse: { select: { id: true, name: true, code: true } } },
        orderBy: balanceSort(q),
        ...pageArgs(q),
      }),
      prisma.warehouseStock.count({ where }),
    ]);
    return { rows: rows.map((r) => ({ ...r, availableQuantity: r.quantity - r.reservedQuantity })), total };
  }

  const where: Prisma.StoreStockWhereInput = {
    ...(storeFilter(context.scope, q.storeId) ? { storeId: storeFilter(context.scope, q.storeId) } : {}),
    product: pWhere,
    ...(q.hideZero ? { OR: [{ quantity: { not: 0 } }, { damagedQuantity: { not: 0 } }] } : {}),
  };
  if (q.lowStock) {
    const filterStoreId = storeFilter(context.scope, q.storeId);
    const ss = await prisma.storeStock.findMany({
      where: filterStoreId ? { storeId: filterStoreId } : {},
      select: { id: true, quantity: true, product: { select: { minimumStock: true } } },
    });
    const ids = ss.filter((s) => s.quantity <= s.product.minimumStock).map((s) => s.id);
    where.id = { in: ids };
  }
  const [rows, total] = await Promise.all([
    prisma.storeStock.findMany({
      where,
      include: { product: { select: productSelect }, store: { select: { id: true, name: true, code: true } } },
      orderBy: balanceSort(q),
      ...pageArgs(q),
    }),
    prisma.storeStock.count({ where }),
  ]);
  return {
    rows: rows.map((r) => {
      const row = { ...r, availableQuantity: r.quantity - r.reservedQuantity };
      if (context.user.role === Role.STORE) {
        const { purchasePrice: _hidden, ...product } = r.product;
        return { ...row, product };
      }
      return row;
    }),
    total,
  };
}

function movementWhere(context: RequestContext, q: MovementListQuery): Prisma.StockMovementWhereInput {
  const where: Prisma.StockMovementWhereInput = {
    ...(q.productId ? { productId: q.productId } : {}),
    ...(q.type ? { type: q.type as MovementType } : {}),
    ...(q.bucket ? { bucket: q.bucket as StockBucket } : {}),
    ...(q.referenceType ? { referenceType: q.referenceType } : {}),
    ...(q.referenceId ? { referenceId: q.referenceId } : {}),
    ...(dateRange(q) ? { createdAt: dateRange(q) } : {}),
  };
  const search = contains(q.search);
  if (search) where.OR = [{ product: { name: search } }, { product: { sku: search } }, { reason: search }];

  const wantsWarehouse = q.locationType === 'WAREHOUSE' || q.warehouseId;
  if (wantsWarehouse) {
    if (context.user.role === Role.STORE) throw ApiError.forbidden();
    where.warehouseId = q.warehouseId ?? { not: null };
  } else if (q.locationType === 'STORE' || q.storeId || !context.scope.all) {
    const filter = storeFilter(context.scope, q.storeId);
    where.storeId = filter ?? { not: null };
  }
  return where;
}

export async function listMovements(context: RequestContext, q: MovementListQuery, take?: number) {
  const where = movementWhere(context, q);
  const [rows, total] = await Promise.all([
    prisma.stockMovement.findMany({
      where,
      include: {
        product: { select: { id: true, name: true, sku: true, unit: true } },
        store: { select: { id: true, name: true, code: true } },
        warehouse: { select: { id: true, name: true, code: true } },
        createdBy: { select: { id: true, name: true } },
      },
      orderBy: orderBy(q, {
        createdAt: (d) => ({ createdAt: d }),
        quantity: (d) => ({ quantity: d }),
        type: (d) => ({ type: d }),
      }, { createdAt: 'desc' }),
      ...(take ? { take } : pageArgs(q)),
    }),
    prisma.stockMovement.count({ where }),
  ]);
  return { rows, total };
}

// ─────────────────────────── Commands ───────────────────────────

async function resolveLocation(
  context: RequestContext,
  input: { locationType: 'WAREHOUSE' | 'STORE'; storeId?: string; warehouseId?: string },
): Promise<{ loc: StockLocation; label: string }> {
  if (input.locationType === 'WAREHOUSE') {
    if (context.user.role !== Role.ADMIN) throw ApiError.forbidden('Only admins can change warehouse stock');
    const warehouse = await resolveWarehouse(prisma, input.warehouseId);
    return { loc: { kind: 'WAREHOUSE', warehouseId: warehouse.id }, label: warehouse.name };
  }
  assertStoreAccess(context.scope, input.storeId);
  const store = await prisma.store.findUnique({ where: { id: input.storeId! }, select: { id: true, name: true, status: true } });
  if (!store) throw ApiError.notFound('Store');
  if (store.status !== RecordStatus.ACTIVE) throw ApiError.invalidState('Store is inactive');
  return { loc: { kind: 'STORE', storeId: store.id }, label: store.name };
}

async function assertProducts(productIds: string[], requireActive = true) {
  const products = await prisma.product.findMany({ where: { id: { in: productIds } }, select: { id: true, status: true, name: true } });
  if (products.length !== new Set(productIds).size) throw ApiError.validation([{ field: 'items', message: 'One or more products do not exist' }]);
  const inactive = products.find((p) => p.status !== RecordStatus.ACTIVE);
  if (requireActive && inactive) throw ApiError.validation([{ field: 'items', message: `${inactive.name} is inactive` }]);
}

/** Opening balance - only allowed where the product has no ledger history yet at that location. */
export async function recordOpeningStock(context: RequestContext, input: z.infer<typeof openingStockSchema>) {
  const { loc, label } = await resolveLocation(context, input);
  if (context.user.role !== Role.ADMIN) throw ApiError.forbidden('Only admins can set opening stock');
  await assertProducts(input.items.map((i) => i.productId));

  return transaction(async (tx) => {
    const existing = await tx.stockMovement.findMany({
      where: {
        productId: { in: input.items.map((i) => i.productId) },
        ...(loc.kind === 'WAREHOUSE' ? { warehouseId: loc.warehouseId } : { storeId: loc.storeId }),
      },
      select: { product: { select: { name: true } } },
      distinct: ['productId'],
    });
    if (existing.length) {
      throw ApiError.invalidState(
        `Opening stock already exists for ${existing.map((e) => e.product.name).join(', ')}. Use a stock adjustment instead.`,
      );
    }
    const movements = [];
    for (const item of input.items) {
      const { movement } = await applyMovement(tx, {
        location: loc,
        productId: item.productId,
        type: MovementType.OPENING,
        quantity: item.quantity,
        referenceType: ReferenceType.OPENING,
        reason: item.reason ?? input.reason ?? 'Opening stock',
        userId: context.user.id,
      });
      movements.push(movement);
    }
    await audit(tx, context, {
      action: 'OPENING_STOCK',
      module: 'stock',
      summary: `Recorded opening stock for ${input.items.length} product(s) at ${label}`,
      newValue: input.items,
    });
    return movements;
  });
}

export async function recordPurchase(context: RequestContext, input: z.infer<typeof purchaseSchema>) {
  const warehouse = await resolveWarehouse(prisma, input.warehouseId);
  await assertProducts(input.items.map((i) => i.productId));
  return transaction(async (tx) => {
    const movements = [];
    for (const item of input.items) {
      const { movement } = await applyMovement(tx, {
        location: { kind: 'WAREHOUSE', warehouseId: warehouse.id },
        productId: item.productId,
        type: MovementType.PURCHASE,
        quantity: item.quantity,
        referenceType: ReferenceType.PURCHASE,
        referenceId: input.supplierReference,
        reason: item.reason ?? input.reason ?? (input.supplierReference ? `Purchase ${input.supplierReference}` : 'Purchase'),
        userId: context.user.id,
      });
      movements.push(movement);
    }
    await audit(tx, context, {
      action: 'PURCHASE',
      module: 'stock',
      recordId: input.supplierReference,
      summary: `Received purchase of ${input.items.reduce((a, i) => a + i.quantity, 0)} units into ${warehouse.name}`,
      newValue: input,
    });
    return movements;
  });
}

export async function recordAdjustment(context: RequestContext, input: z.infer<typeof adjustmentSchema>) {
  const { loc, label } = await resolveLocation(context, input);
  await assertProducts(input.items.map((i) => i.productId), false);
  return transaction(async (tx) => {
    const movements = [];
    for (const item of input.items) {
      const { movement } = await applyMovement(tx, {
        location: loc,
        productId: item.productId,
        type: MovementType.ADJUSTMENT,
        bucket: input.bucket as StockBucket,
        quantity: item.quantity,
        referenceType: ReferenceType.ADJUSTMENT,
        reason: input.reason,
        userId: context.user.id,
      });
      movements.push(movement);
    }
    await audit(tx, context, {
      action: 'ADJUSTMENT',
      module: 'stock',
      summary: `Adjusted ${input.bucket.toLowerCase()} stock of ${input.items.length} product(s) at ${label}: ${input.reason}`,
      newValue: input,
    });
    return movements;
  });
}

/** Moves stock from available to the damaged bucket. */
export async function reportDamage(context: RequestContext, input: z.infer<typeof damageSchema>) {
  const { loc, label } = await resolveLocation(context, input);
  await assertProducts(input.items.map((i) => i.productId), false);
  return transaction(async (tx) => {
    for (const item of input.items) {
      await moveToDamaged(tx, {
        location: loc,
        productId: item.productId,
        quantity: item.quantity,
        referenceType: ReferenceType.DAMAGE_REPORT,
        reason: item.reason,
        userId: context.user.id,
      });
    }
    await audit(tx, context, {
      action: 'DAMAGE_REPORT',
      module: 'stock',
      summary: `Reported ${input.items.reduce((a, i) => a + i.quantity, 0)} damaged unit(s) at ${label}`,
      newValue: input.items,
    });
    await notify(tx, {
      type: NotificationType.DAMAGE_REPORTED,
      title: 'Damaged stock reported',
      message: `${context.user.name} reported ${input.items.length} damaged product line(s) at ${label}.`,
      entityType: 'STOCK',
      admins: true,
      storeIds: loc.kind === 'STORE' ? [loc.storeId] : undefined,
      managersOnly: true,
      excludeUserId: context.user.id,
    });
    return { reported: input.items.length };
  });
}

/** Disposes damaged stock (removes it from the damaged bucket). */
export async function writeOffDamaged(context: RequestContext, input: z.infer<typeof writeOffSchema>) {
  if (context.user.role === Role.STORE) throw ApiError.forbidden();
  const { loc, label } = await resolveLocation(context, input);
  return transaction(async (tx) => {
    for (const item of input.items) {
      await applyMovement(tx, {
        location: loc,
        productId: item.productId,
        type: MovementType.ADJUSTMENT,
        bucket: StockBucket.DAMAGED,
        quantity: -item.quantity,
        referenceType: ReferenceType.ADJUSTMENT,
        reason: `Write-off: ${item.reason}`,
        userId: context.user.id,
      });
    }
    await audit(tx, context, {
      action: 'DAMAGE_WRITE_OFF',
      module: 'stock',
      summary: `Wrote off ${input.items.reduce((a, i) => a + i.quantity, 0)} damaged unit(s) at ${label}`,
      newValue: input.items,
    });
    return { writtenOff: input.items.length };
  });
}

/**
 * Removes a stale stock balance row. Only allowed when quantity, reserved and
 * damaged are all zero - there is never anything to lose, and the ledger
 * movements that produced that zero balance are untouched and permanent.
 */
export async function deleteStockBalance(context: RequestContext, id: string, locationType: 'WAREHOUSE' | 'STORE') {
  if (locationType === 'WAREHOUSE') {
    if (context.user.role !== Role.ADMIN) throw ApiError.forbidden('Only admins can remove warehouse stock records');
    const row = await prisma.warehouseStock.findUnique({ where: { id }, include: { product: { select: { name: true } } } });
    if (!row) throw ApiError.notFound('Stock record');
    if (row.quantity !== 0 || row.reservedQuantity !== 0 || row.damagedQuantity !== 0) {
      throw ApiError.invalidState('Only stock records with zero quantity, reserved and damaged can be removed');
    }
    await transaction(async (tx) => {
      await tx.warehouseStock.delete({ where: { id } });
      await audit(tx, context, { action: 'DELETE', module: 'stock', recordId: id, summary: `Removed empty warehouse stock record for ${row.product.name}` });
    });
  } else {
    const row = await prisma.storeStock.findUnique({ where: { id }, include: { product: { select: { name: true } } } });
    if (!row) throw ApiError.notFound('Stock record');
    assertStoreAccess(context.scope, row.storeId);
    if (row.quantity !== 0 || row.reservedQuantity !== 0 || row.damagedQuantity !== 0) {
      throw ApiError.invalidState('Only stock records with zero quantity, reserved and damaged can be removed');
    }
    await transaction(async (tx) => {
      await tx.storeStock.delete({ where: { id } });
      await audit(tx, context, { action: 'DELETE', module: 'stock', recordId: id, summary: `Removed empty store stock record for ${row.product.name}` });
    });
  }
  return { deleted: true };
}

// ─────────────────────────── Store availability ───────────────────────────

export async function submitAvailability(context: RequestContext, input: z.infer<typeof availabilitySchema>) {
  const storeId = context.user.role === Role.STORE ? context.user.storeId! : input.storeId;
  if (!storeId) throw ApiError.validation([{ field: 'storeId', message: 'Select a store' }]);
  assertStoreAccess(context.scope, storeId);
  await assertProducts(input.items.map((i) => i.productId));

  return transaction(async (tx) => {
    for (const item of input.items) {
      await tx.storeAvailability.upsert({
        where: { storeId_productId: { storeId, productId: item.productId } },
        create: { storeId, productId: item.productId, quantity: item.quantity, notes: input.notes, submittedById: context.user.id },
        update: { quantity: item.quantity, notes: input.notes, submittedById: context.user.id },
      });
    }
    await audit(tx, context, {
      action: 'SUBMIT_AVAILABILITY',
      module: 'stock',
      recordId: storeId,
      summary: `Submitted available quantities for ${input.items.length} product(s)`,
      newValue: input.items,
    });
    return { submitted: input.items.length };
  });
}

export async function listAvailability(context: RequestContext, q: z.infer<typeof stockListQuery>) {
  const search = contains(q.search);
  const where: Prisma.StoreAvailabilityWhereInput = {
    ...(storeFilter(context.scope, q.storeId) ? { storeId: storeFilter(context.scope, q.storeId) } : {}),
    ...(q.productId ? { productId: q.productId } : {}),
    ...(search ? { product: { OR: [{ name: search }, { sku: search }] } } : {}),
  };
  const [rows, total] = await Promise.all([
    prisma.storeAvailability.findMany({
      where,
      include: {
        product: { select: { id: true, name: true, sku: true, unit: true } },
        store: { select: { id: true, name: true, code: true } },
      },
      orderBy: [{ product: { name: 'asc' } }, { store: { name: 'asc' } }],
      ...pageArgs(q),
    }),
    prisma.storeAvailability.count({ where }),
  ]);
  return { rows, total };
}

/**
 * Cross-store view: for each product, the declared availability and system
 * stock per store, plus totals. Used to spot inter-store transfer candidates.
 */
export async function availabilityMatrix(context: RequestContext, q: z.infer<typeof stockListQuery>) {
  if (context.user.role === Role.STORE) throw ApiError.forbidden();
  const search = contains(q.search);
  const stores = await prisma.store.findMany({
    where: { status: RecordStatus.ACTIVE, ...(context.scope.all ? {} : { id: { in: context.scope.storeIds } }) },
    select: { id: true, name: true, code: true },
    orderBy: { name: 'asc' },
  });
  const storeIds = stores.map((s) => s.id);
  const productWhereInput: Prisma.ProductWhereInput = {
    status: RecordStatus.ACTIVE,
    ...(q.categoryId ? { categoryId: { in: await categoryWithDescendants(q.categoryId) } } : {}),
    // Only products that are declared or stocked in at least one visible store.
    AND: [
      ...(search ? [{ OR: [{ name: search }, { sku: search }] }] : []),
      { OR: [{ storeAvailability: { some: { storeId: { in: storeIds } } } }, { storeStock: { some: { storeId: { in: storeIds }, quantity: { gt: 0 } } } }] },
    ],
  };
  const [products, total] = await Promise.all([
    prisma.product.findMany({
      where: productWhereInput,
      select: { id: true, name: true, sku: true, unit: true, minimumStock: true },
      orderBy: { name: 'asc' },
      ...pageArgs(q),
    }),
    prisma.product.count({ where: productWhereInput }),
  ]);
  const productIds = products.map((p) => p.id);
  const [declared, system] = await Promise.all([
    prisma.storeAvailability.findMany({ where: { productId: { in: productIds }, storeId: { in: storeIds } } }),
    prisma.storeStock.findMany({ where: { productId: { in: productIds }, storeId: { in: storeIds } } }),
  ]);

  const rows = products.map((p) => {
    const perStore = stores.map((s) => {
      const d = declared.find((x) => x.productId === p.id && x.storeId === s.id);
      const st = system.find((x) => x.productId === p.id && x.storeId === s.id);
      return {
        storeId: s.id,
        declaredQuantity: d?.quantity ?? null,
        declaredAt: d?.updatedAt ?? null,
        systemQuantity: st?.quantity ?? 0,
      };
    });
    return {
      product: p,
      stores: perStore,
      totalDeclared: perStore.reduce((a, s) => a + (s.declaredQuantity ?? 0), 0),
      totalSystem: perStore.reduce((a, s) => a + s.systemQuantity, 0),
    };
  });
  return { stores, rows, total };
}
