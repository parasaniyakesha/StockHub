import { MovementType, Prisma, ReturnCondition, Role, SaleStatus, StockBucket, RecordStatus } from '@prisma/client';
import { z } from 'zod';
import { prisma, transaction } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { contains, dateRange, orderBy, pageArgs } from '../utils/pagination';
import { nextDocumentNumber } from '../utils/numbering';
import { D, round2 } from '../utils/money';
import { assertRecordInScope, assertStoreAccess, storeFilter } from '../middleware/storeScope';
import { RequestContext } from '../types/auth';
import { applyMovement, ReferenceType } from './stockLedger.service';
import { audit } from './audit.service';
import { notify, NotificationType } from './notification.service';
import { createReturnSchema, returnListQuery } from '../validators/operations.validator';

const include = {
  store: { select: { id: true, name: true, code: true } },
  sale: { select: { id: true, invoiceNumber: true, createdAt: true } },
  createdBy: { select: { id: true, name: true } },
  items: { include: { product: { select: { id: true, name: true, sku: true, unit: true } } } },
} satisfies Prisma.SaleReturnInclude;

export async function listReturns(context: RequestContext, q: z.infer<typeof returnListQuery>) {
  const search = contains(q.search);
  const where: Prisma.SaleReturnWhereInput = {
    ...(storeFilter(context.scope, q.storeId) ? { storeId: storeFilter(context.scope, q.storeId) } : {}),
    ...(dateRange(q) ? { createdAt: dateRange(q) } : {}),
    ...(q.condition ? { items: { some: { condition: q.condition as ReturnCondition } } } : {}),
    ...(q.productId ? { items: { some: { productId: q.productId } } } : {}),
    ...(search ? { OR: [{ returnNumber: search }, { sale: { invoiceNumber: search } }, { notes: search }] } : {}),
  };
  const [rows, total] = await Promise.all([
    prisma.saleReturn.findMany({
      where,
      include,
      orderBy: orderBy(q, {
        returnNumber: (d) => ({ returnNumber: d }),
        createdAt: (d) => ({ createdAt: d }),
        refundAmount: (d) => ({ refundAmount: d }),
      }, { createdAt: 'desc' }),
      ...pageArgs(q),
    }),
    prisma.saleReturn.count({ where }),
  ]);
  return {
    rows: rows.map((r) => ({
      ...r,
      totalQuantity: r.items.reduce((a, i) => a + i.quantity, 0),
      goodQuantity: r.items.filter((i) => i.condition === ReturnCondition.GOOD).reduce((a, i) => a + i.quantity, 0),
      damagedQuantity: r.items.filter((i) => i.condition === ReturnCondition.DAMAGED).reduce((a, i) => a + i.quantity, 0),
    })),
    total,
  };
}

export async function getReturn(context: RequestContext, id: string) {
  const record = await prisma.saleReturn.findUnique({ where: { id }, include });
  if (!record) throw ApiError.notFound('Return');
  assertRecordInScope(context.scope, [record.storeId], 'Return');
  return record;
}

/**
 * Good items go back to available stock; damaged items go to the damaged bucket.
 * When linked to a sale, quantities are capped at (sold - already returned).
 */
export async function createReturn(context: RequestContext, input: z.infer<typeof createReturnSchema>) {
  const storeId = context.user.role === Role.STORE ? context.user.storeId! : input.storeId;
  if (!storeId) throw ApiError.validation([{ field: 'storeId', message: 'Select a store' }]);
  assertStoreAccess(context.scope, storeId);

  if (input.clientRequestId) {
    const existing = await prisma.saleReturn.findUnique({ where: { clientRequestId: input.clientRequestId }, select: { id: true } });
    if (existing) return getReturn(context, existing.id);
  }

  const id = await transaction(async (tx) => {
    const store = await tx.store.findUnique({ where: { id: storeId }, select: { name: true, status: true } });
    if (!store) throw ApiError.notFound('Store');
    if (store.status !== RecordStatus.ACTIVE) throw ApiError.invalidState('Store is inactive');

    let saleItems: { id: string; productId: string; quantity: number; total: Prisma.Decimal }[] = [];
    if (input.saleId) {
      const sale = await tx.sale.findUnique({ where: { id: input.saleId }, include: { items: true } });
      if (!sale || sale.storeId !== storeId) throw ApiError.validation([{ field: 'saleId', message: 'Sale not found for this store' }]);
      if (sale.status !== SaleStatus.COMPLETED) throw ApiError.invalidState('Returns cannot be recorded against a cancelled sale');
      saleItems = sale.items;
    }

    const products = await tx.product.findMany({ where: { id: { in: input.items.map((i) => i.productId) } } });
    const planned = [];
    for (const [index, item] of input.items.entries()) {
      const product = products.find((p) => p.id === item.productId);
      if (!product) throw ApiError.validation([{ field: `items.${index}.productId`, message: 'Product does not exist' }]);
      let unitPrice = D(product.sellingPrice);
      let saleItemId: string | null = null;
      if (input.saleId) {
        const saleItem = saleItems.find((s) => s.productId === item.productId);
        if (!saleItem) throw ApiError.validation([{ field: `items.${index}.productId`, message: `${product.name} is not on this invoice` }]);
        const already = await tx.saleReturnItem.aggregate({ where: { saleItemId: saleItem.id }, _sum: { quantity: true } });
        const remaining = saleItem.quantity - (already._sum.quantity ?? 0);
        if (item.quantity > remaining) {
          throw ApiError.validation([{ field: `items.${index}.quantity`, message: `Only ${remaining} unit(s) of ${product.name} can still be returned` }]);
        }
        unitPrice = round2(saleItem.total.div(saleItem.quantity));
        saleItemId = saleItem.id;
      }
      planned.push({ product, item, unitPrice, saleItemId });
    }
    const refundAmount = round2(planned.reduce((a, p) => a.plus(p.unitPrice.mul(p.item.quantity)), D(0)));

    const record = await tx.saleReturn.create({
      data: {
        returnNumber: await nextDocumentNumber(tx, 'RET'),
        storeId,
        saleId: input.saleId ?? null,
        notes: input.notes,
        refundAmount,
        clientRequestId: input.clientRequestId,
        createdById: context.user.id,
        items: {
          create: planned.map((p) => ({
            productId: p.product.id,
            saleItemId: p.saleItemId,
            quantity: p.item.quantity,
            condition: p.item.condition as ReturnCondition,
            reason: p.item.reason,
            unitPrice: p.unitPrice,
          })),
        },
      },
    });

    for (const p of planned) {
      await applyMovement(tx, {
        location: { kind: 'STORE', storeId },
        productId: p.product.id,
        type: MovementType.RETURN,
        bucket: p.item.condition === 'DAMAGED' ? StockBucket.DAMAGED : StockBucket.AVAILABLE,
        quantity: p.item.quantity,
        referenceType: ReferenceType.RETURN,
        referenceId: record.id,
        reason: `${record.returnNumber} (${p.item.condition.toLowerCase()}): ${p.item.reason}`,
        userId: context.user.id,
      });
    }
    await audit(tx, context, {
      action: 'CREATE',
      module: 'returns',
      recordId: record.id,
      summary: `Recorded return ${record.returnNumber} at ${store.name}`,
      newValue: input,
    });
    if (planned.some((p) => p.item.condition === 'DAMAGED')) {
      await notify(tx, {
        type: NotificationType.RETURN_RECORDED,
        title: 'Damaged return recorded',
        message: `${store.name} recorded return ${record.returnNumber} with damaged items.`,
        entityType: 'RETURN',
        entityId: record.id,
        admins: true,
        storeIds: [storeId],
        managersOnly: true,
        excludeUserId: context.user.id,
      });
    }
    return record.id;
  });
  return getReturn(context, id);
}
