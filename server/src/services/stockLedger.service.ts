import { MovementType, StockBucket } from '@prisma/client';
import { Tx } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { notify, NotificationType } from './notification.service';
import { getSettings } from './settings.service';

/**
 * ─────────────────────────── STOCK LEDGER ───────────────────────────
 * The single place where stock balances change. Every change:
 *   1. updates the balance row with validation, and
 *   2. writes a StockMovement row with the signed quantity and balance after.
 * Callers MUST pass a transaction client so the business document (sale,
 * transfer, packing order ...) and its movements commit or roll back together.
 */

export type StockLocation = { kind: 'WAREHOUSE'; warehouseId: string } | { kind: 'STORE'; storeId: string };

export const ReferenceType = {
  OPENING: 'OPENING',
  PURCHASE: 'PURCHASE',
  ADJUSTMENT: 'ADJUSTMENT',
  DAMAGE_REPORT: 'DAMAGE_REPORT',
  SALE: 'SALE',
  SALE_CANCELLATION: 'SALE_CANCELLATION',
  RETURN: 'RETURN',
  PACKING_ORDER: 'PACKING_ORDER',
  TRANSFER: 'TRANSFER',
} as const;

export interface MovementInput {
  location: StockLocation;
  productId: string;
  type: MovementType;
  /** Signed change. Positive adds stock, negative removes it. Never 0. */
  quantity: number;
  bucket?: StockBucket;
  /** Reserved quantity consumed by this movement (e.g. dispatching a reserved allocation). */
  releaseReserved?: number;
  referenceType?: string;
  referenceId?: string;
  reason?: string;
  userId: string;
  /** Override the global allowNegativeStock setting for this movement. */
  allowNegative?: boolean;
}

interface BalanceRow {
  quantity: number;
  reservedQuantity: number;
  damagedQuantity: number;
}

/** Makes sure the balance row exists (quantity 0) without touching an existing one. */
async function ensureRow(tx: Tx, loc: StockLocation, productId: string) {
  if (loc.kind === 'WAREHOUSE') {
    await tx.warehouseStock.upsert({
      where: { warehouseId_productId: { warehouseId: loc.warehouseId, productId } },
      create: { warehouseId: loc.warehouseId, productId, quantity: 0, reservedQuantity: 0, damagedQuantity: 0 },
      update: {},
    });
  } else {
    await tx.storeStock.upsert({
      where: { storeId_productId: { storeId: loc.storeId, productId } },
      create: { storeId: loc.storeId, productId, quantity: 0, reservedQuantity: 0, damagedQuantity: 0 },
      update: {},
    });
  }
}

async function productInfo(tx: Tx, productId: string) {
  const product = await tx.product.findUnique({
    where: { id: productId },
    select: { id: true, name: true, sku: true, minimumStock: true },
  });
  if (!product) throw ApiError.badRequest('Product does not exist');
  return product;
}

function describe(loc: StockLocation) {
  return loc.kind === 'WAREHOUSE' ? 'the warehouse' : 'this store';
}

export async function applyMovement(tx: Tx, input: MovementInput) {
  if (!Number.isInteger(input.quantity) || input.quantity === 0) {
    throw ApiError.badRequest('Movement quantity must be a non-zero whole number');
  }
  const bucket = input.bucket ?? StockBucket.AVAILABLE;
  const release = input.releaseReserved ?? 0;
  const delta = input.quantity;
  const loc = input.location;
  const product = await productInfo(tx, input.productId);

  const allowNegative =
    bucket === StockBucket.AVAILABLE && (input.allowNegative ?? (await getSettings(tx)).allowNegativeStock);

  await ensureRow(tx, loc, input.productId);

  let balance: BalanceRow;
  if (loc.kind === 'WAREHOUSE') {
    const current = await tx.warehouseStock.findUniqueOrThrow({
      where: { warehouseId_productId: { warehouseId: loc.warehouseId, productId: input.productId } },
    });
    if (bucket === StockBucket.AVAILABLE) {
      if (current.reservedQuantity - release < 0) {
        throw ApiError.insufficientStock(`Insufficient stock for ${product.name} (${product.sku}) in ${describe(loc)}`);
      }
      if (delta < 0 && !allowNegative && current.quantity + delta - (current.reservedQuantity - release) < 0) {
        throw ApiError.insufficientStock(`Insufficient stock for ${product.name} (${product.sku}) in ${describe(loc)}`);
      }
      balance = await tx.warehouseStock.update({
        where: { id: current.id },
        data: {
          quantity: { increment: delta },
          reservedQuantity: { decrement: release },
        },
        select: { quantity: true, reservedQuantity: true, damagedQuantity: true },
      });
    } else {
      if (current.damagedQuantity + delta < 0) {
        throw ApiError.insufficientStock(
          `Insufficient damaged stock for ${product.name} (${product.sku}) in ${describe(loc)}`,
        );
      }
      balance = await tx.warehouseStock.update({
        where: { id: current.id },
        data: {
          damagedQuantity: { increment: delta },
        },
        select: { quantity: true, reservedQuantity: true, damagedQuantity: true },
      });
    }
  } else {
    const current = await tx.storeStock.findUniqueOrThrow({
      where: { storeId_productId: { storeId: loc.storeId, productId: input.productId } },
    });
    if (bucket === StockBucket.AVAILABLE) {
      if (current.reservedQuantity - release < 0) {
        throw ApiError.insufficientStock(`Insufficient stock for ${product.name} (${product.sku}) in ${describe(loc)}`);
      }
      if (delta < 0 && !allowNegative && current.quantity + delta - (current.reservedQuantity - release) < 0) {
        throw ApiError.insufficientStock(`Insufficient stock for ${product.name} (${product.sku}) in ${describe(loc)}`);
      }
      balance = await tx.storeStock.update({
        where: { id: current.id },
        data: {
          quantity: { increment: delta },
          reservedQuantity: { decrement: release },
        },
        select: { quantity: true, reservedQuantity: true, damagedQuantity: true },
      });
    } else {
      if (current.damagedQuantity + delta < 0) {
        throw ApiError.insufficientStock(
          `Insufficient damaged stock for ${product.name} (${product.sku}) in ${describe(loc)}`,
        );
      }
      balance = await tx.storeStock.update({
        where: { id: current.id },
        data: {
          damagedQuantity: { increment: delta },
        },
        select: { quantity: true, reservedQuantity: true, damagedQuantity: true },
      });
    }
  }

  const balanceAfter = bucket === StockBucket.AVAILABLE ? balance.quantity : balance.damagedQuantity;

  const movement = await tx.stockMovement.create({
    data: {
      productId: input.productId,
      storeId: loc.kind === 'STORE' ? loc.storeId : null,
      warehouseId: loc.kind === 'WAREHOUSE' ? loc.warehouseId : null,
      type: input.type,
      bucket,
      quantity: delta,
      balanceAfter,
      referenceType: input.referenceType,
      referenceId: input.referenceId,
      reason: input.reason?.slice(0, 500),
      createdById: input.userId,
    },
  });

  // Low-stock alert only when this movement crosses the threshold downward.
  if (bucket === StockBucket.AVAILABLE && delta < 0 && product.minimumStock > 0) {
    const before = balance.quantity - delta;
    if (before > product.minimumStock && balance.quantity <= product.minimumStock) {
      const settings = await getSettings(tx);
      if (settings.lowStockAlerts) {
        await notify(tx, {
          type: NotificationType.LOW_STOCK,
          title: 'Low stock detected',
          message: `${product.name} (${product.sku}) is at ${balance.quantity} in ${
            loc.kind === 'WAREHOUSE' ? 'the central warehouse' : 'store'
          } (minimum ${product.minimumStock}).`,
          entityType: 'PRODUCT',
          entityId: product.id,
          admins: true,
          storeIds: loc.kind === 'STORE' ? [loc.storeId] : undefined,
        });
      }
    }
  }

  return { movement, balance };
}

/**
 * Reserves available stock for a pending outbound document (assigned packing
 * order / approved transfer). No movement is written: on-hand quantity is
 * unchanged, only availability for other operations is reduced.
 */
export async function reserve(tx: Tx, loc: StockLocation, productId: string, quantity: number) {
  if (quantity <= 0) return;
  await ensureRow(tx, loc, productId);
  if (loc.kind === 'WAREHOUSE') {
    const current = await tx.warehouseStock.findUniqueOrThrow({
      where: { warehouseId_productId: { warehouseId: loc.warehouseId, productId } },
    });
    if (current.quantity - current.reservedQuantity < quantity) {
      const product = await productInfo(tx, productId);
      throw ApiError.insufficientStock(
        `Not enough available stock of ${product.name} (${product.sku}) in ${describe(loc)} to allocate ${quantity}`,
      );
    }
    await tx.warehouseStock.update({
      where: { id: current.id },
      data: { reservedQuantity: { increment: quantity } },
    });
  } else {
    const current = await tx.storeStock.findUniqueOrThrow({
      where: { storeId_productId: { storeId: loc.storeId, productId } },
    });
    if (current.quantity - current.reservedQuantity < quantity) {
      const product = await productInfo(tx, productId);
      throw ApiError.insufficientStock(
        `Not enough available stock of ${product.name} (${product.sku}) in ${describe(loc)} to allocate ${quantity}`,
      );
    }
    await tx.storeStock.update({
      where: { id: current.id },
      data: { reservedQuantity: { increment: quantity } },
    });
  }
}

export async function releaseReservation(tx: Tx, loc: StockLocation, productId: string, quantity: number) {
  if (quantity <= 0) return;
  if (loc.kind === 'WAREHOUSE') {
    const current = await tx.warehouseStock.findUnique({
      where: { warehouseId_productId: { warehouseId: loc.warehouseId, productId } },
    });
    if (!current) throw ApiError.invalidState('No reservation to release');
    await tx.warehouseStock.update({
      where: { id: current.id },
      data: { reservedQuantity: Math.max(0, current.reservedQuantity - quantity) },
    });
  } else {
    const current = await tx.storeStock.findUnique({
      where: { storeId_productId: { storeId: loc.storeId, productId } },
    });
    if (!current) throw ApiError.invalidState('No reservation to release');
    await tx.storeStock.update({
      where: { id: current.id },
      data: { reservedQuantity: Math.max(0, current.reservedQuantity - quantity) },
    });
  }
}

/** Moves quantity from AVAILABLE to DAMAGED at the same location (two movements). */
export async function moveToDamaged(
  tx: Tx,
  input: Omit<MovementInput, 'type' | 'bucket' | 'quantity'> & { quantity: number },
) {
  const out = await applyMovement(tx, { ...input, type: MovementType.DAMAGE, quantity: -input.quantity });
  const into = await applyMovement(tx, {
    ...input,
    type: MovementType.DAMAGE,
    bucket: StockBucket.DAMAGED,
    quantity: input.quantity,
  });
  return { out, into };
}
