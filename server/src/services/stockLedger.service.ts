import { MovementType, Prisma, StockBucket } from '@prisma/client';
import { Tx } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { notify, NotificationType } from './notification.service';
import { getSettings } from './settings.service';

/**
 * ─────────────────────────── STOCK LEDGER ───────────────────────────
 * The single place where stock balances change. Every change:
 *   1. atomically updates the cached balance with a conditional UPDATE
 *      (so concurrent requests cannot oversell / go negative), and
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

const table = (loc: StockLocation) =>
  loc.kind === 'WAREHOUSE' ? Prisma.raw('warehouse_stock') : Prisma.raw('store_stock');

const locationColumn = (loc: StockLocation) =>
  loc.kind === 'WAREHOUSE' ? Prisma.raw('"warehouseId"') : Prisma.raw('"storeId"');

const locationId = (loc: StockLocation) => (loc.kind === 'WAREHOUSE' ? loc.warehouseId : loc.storeId);

/** Makes sure the balance row exists (quantity 0) without touching an existing one. */
async function ensureRow(tx: Tx, loc: StockLocation, productId: string) {
  await tx.$executeRaw`
    INSERT INTO ${table(loc)} (id, ${locationColumn(loc)}, "productId", quantity, "reservedQuantity", "damagedQuantity", "updatedAt")
    VALUES (gen_random_uuid(), ${locationId(loc)}, ${productId}, 0, 0, 0, now())
    ON CONFLICT (${locationColumn(loc)}, "productId") DO NOTHING`;
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

  let rows: BalanceRow[];
  if (bucket === StockBucket.AVAILABLE) {
    // available = quantity - reservedQuantity must stay >= 0 after the change,
    // unless negative stock is explicitly allowed. Increases are never blocked.
    rows = await tx.$queryRaw<BalanceRow[]>`
      UPDATE ${table(loc)}
      SET quantity = quantity + ${delta},
          "reservedQuantity" = "reservedQuantity" - ${release},
          "updatedAt" = now()
      WHERE ${locationColumn(loc)} = ${locationId(loc)} AND "productId" = ${input.productId}
        AND "reservedQuantity" - ${release} >= 0
        AND (${delta} > 0 OR ${allowNegative} OR quantity + ${delta} - ("reservedQuantity" - ${release}) >= 0)
      RETURNING quantity, "reservedQuantity", "damagedQuantity"`;
  } else {
    rows = await tx.$queryRaw<BalanceRow[]>`
      UPDATE ${table(loc)}
      SET "damagedQuantity" = "damagedQuantity" + ${delta}, "updatedAt" = now()
      WHERE ${locationColumn(loc)} = ${locationId(loc)} AND "productId" = ${input.productId}
        AND "damagedQuantity" + ${delta} >= 0
      RETURNING quantity, "reservedQuantity", "damagedQuantity"`;
  }

  if (!rows.length) {
    throw ApiError.insufficientStock(
      `Insufficient ${bucket === StockBucket.DAMAGED ? 'damaged ' : ''}stock for ${product.name} (${product.sku}) in ${describe(loc)}`,
    );
  }

  const balance = rows[0];
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
  const rows = await tx.$queryRaw<BalanceRow[]>`
    UPDATE ${table(loc)}
    SET "reservedQuantity" = "reservedQuantity" + ${quantity}, "updatedAt" = now()
    WHERE ${locationColumn(loc)} = ${locationId(loc)} AND "productId" = ${productId}
      AND quantity - "reservedQuantity" >= ${quantity}
    RETURNING quantity, "reservedQuantity", "damagedQuantity"`;
  if (!rows.length) {
    const product = await productInfo(tx, productId);
    throw ApiError.insufficientStock(
      `Not enough available stock of ${product.name} (${product.sku}) in ${describe(loc)} to allocate ${quantity}`,
    );
  }
}

export async function releaseReservation(tx: Tx, loc: StockLocation, productId: string, quantity: number) {
  if (quantity <= 0) return;
  const count = await tx.$executeRaw`
    UPDATE ${table(loc)}
    SET "reservedQuantity" = GREATEST("reservedQuantity" - ${quantity}, 0), "updatedAt" = now()
    WHERE ${locationColumn(loc)} = ${locationId(loc)} AND "productId" = ${productId}`;
  if (!count) throw ApiError.invalidState('No reservation to release');
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
