import { MovementType, PaymentMethod, Prisma, RecordStatus, Role, SaleStatus } from '@prisma/client';
import { z } from 'zod';
import { prisma, transaction } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { contains, dateRange, orderBy, pageArgs } from '../utils/pagination';
import { nextSequence } from '../utils/numbering';
import { D, round2 } from '../utils/money';
import { assertRecordInScope, assertStoreAccess, storeFilter } from '../middleware/storeScope';
import { RequestContext } from '../types/auth';
import { applyMovement, ReferenceType } from './stockLedger.service';
import { audit } from './audit.service';
import { getSettings } from './settings.service';
import { createSaleSchema, saleListQuery } from '../validators/operations.validator';

const detailInclude = {
  store: { select: { id: true, name: true, code: true, address: true, city: true, phone: true } },
  createdBy: { select: { id: true, name: true } },
  items: { include: { product: { select: { id: true, name: true, sku: true, unit: true } } } },
  returns: { select: { id: true, returnNumber: true, refundAmount: true, createdAt: true } },
} satisfies Prisma.SaleInclude;

export function saleWhere(context: RequestContext, q: z.infer<typeof saleListQuery>): Prisma.SaleWhereInput {
  const search = contains(q.search);
  return {
    ...(storeFilter(context.scope, q.storeId) ? { storeId: storeFilter(context.scope, q.storeId) } : {}),
    ...(q.status ? { status: q.status as SaleStatus } : {}),
    ...(q.paymentMethod ? { paymentMethod: q.paymentMethod as PaymentMethod } : {}),
    ...(dateRange(q) ? { createdAt: dateRange(q) } : {}),
    ...(q.productId ? { items: { some: { productId: q.productId } } } : {}),
    ...(search ? { OR: [{ invoiceNumber: search }, { customerName: search }, { customerPhone: search }] } : {}),
  };
}

export async function listSales(context: RequestContext, q: z.infer<typeof saleListQuery>) {
  const where = saleWhere(context, q);
  const [rows, total, sums] = await Promise.all([
    prisma.sale.findMany({
      where,
      include: { store: { select: { id: true, name: true, code: true } }, createdBy: { select: { id: true, name: true } }, _count: { select: { items: true } } },
      orderBy: orderBy(q, {
        invoiceNumber: (d) => ({ invoiceNumber: d }),
        grandTotal: (d) => ({ grandTotal: d }),
        createdAt: (d) => ({ createdAt: d }),
        store: (d) => ({ store: { name: d } }),
        customerName: (d) => ({ customerName: d }),
      }, { createdAt: 'desc' }),
      ...pageArgs(q),
    }),
    prisma.sale.count({ where }),
    prisma.sale.aggregate({ where: { ...where, status: SaleStatus.COMPLETED }, _sum: { grandTotal: true }, _count: true }),
  ]);
  return { rows, total, summary: { completedCount: sums._count, completedTotal: sums._sum.grandTotal ?? D(0) } };
}

export async function getSale(context: RequestContext, id: string) {
  const sale = await prisma.sale.findUnique({ where: { id }, include: detailInclude });
  if (!sale) throw ApiError.notFound('Sale');
  assertRecordInScope(context.scope, [sale.storeId], 'Sale');
  const returned = await prisma.saleReturnItem.groupBy({ by: ['saleItemId'], where: { saleItem: { saleId: id } }, _sum: { quantity: true } });
  return {
    ...sale,
    items: sale.items.map((i) => ({ ...i, returnedQuantity: returned.find((r) => r.saleItemId === i.id)?._sum.quantity ?? 0 })),
  };
}

/**
 * Records a completed sale atomically:
 *   Sale + SaleItems + SALE stock movements (store stock decreases).
 * If any line has insufficient stock the whole sale rolls back.
 * Idempotent on clientRequestId: re-submitting returns the original sale.
 */
export async function createSale(context: RequestContext, input: z.infer<typeof createSaleSchema>) {
  const storeId = context.user.role === Role.STORE ? context.user.storeId! : input.storeId;
  if (!storeId) throw ApiError.validation([{ field: 'storeId', message: 'Select a store' }]);
  assertStoreAccess(context.scope, storeId);

  if (input.clientRequestId) {
    const existing = await prisma.sale.findUnique({ where: { clientRequestId: input.clientRequestId }, select: { id: true, storeId: true } });
    if (existing) return { sale: await getSale(context, existing.id), duplicate: true };
  }

  const settings = await getSettings();
  const id = await transaction(async (tx) => {
    const store = await tx.store.findUnique({ where: { id: storeId }, select: { id: true, code: true, name: true, status: true } });
    if (!store) throw ApiError.notFound('Store');
    if (store.status !== RecordStatus.ACTIVE) throw ApiError.invalidState('Store is inactive');

    const products = await tx.product.findMany({ where: { id: { in: input.items.map((i) => i.productId) } } });
    const lines = input.items.map((item, index) => {
      const product = products.find((p) => p.id === item.productId);
      if (!product) throw ApiError.validation([{ field: `items.${index}.productId`, message: 'Product does not exist' }]);
      if (product.status !== RecordStatus.ACTIVE) throw ApiError.validation([{ field: `items.${index}.productId`, message: `${product.name} is not for sale` }]);

      const overridden = item.unitPrice !== undefined && !D(item.unitPrice).equals(product.sellingPrice);
      if (overridden && !settings.allowPriceOverride && context.user.role === Role.STORE) {
        throw ApiError.validation([{ field: `items.${index}.unitPrice`, message: 'Price override is not allowed' }]);
      }
      const unitPrice = round2(D(item.unitPrice ?? product.sellingPrice));
      const gross = unitPrice.mul(item.quantity);
      const discount = round2(D(item.discount ?? 0));
      if (discount.greaterThan(gross)) throw ApiError.validation([{ field: `items.${index}.discount`, message: 'Discount cannot exceed the line amount' }]);
      const taxable = gross.minus(discount);
      const tax = round2(taxable.mul(product.taxRate).div(100));
      return { product, quantity: item.quantity, unitPrice, discount, taxRate: product.taxRate, tax, net: round2(taxable), total: round2(taxable.plus(tax)) };
    });

    const subtotal = lines.reduce((a, l) => a.plus(l.net), D(0));
    const tax = lines.reduce((a, l) => a.plus(l.tax), D(0));
    const discount = round2(D(input.discount ?? 0));
    const beforeDiscount = subtotal.plus(tax);
    if (discount.greaterThan(beforeDiscount)) throw ApiError.validation([{ field: 'discount', message: 'Discount cannot exceed the invoice total' }]);
    const grandTotal = round2(beforeDiscount.minus(discount));

    const seq = await nextSequence(tx, `INV-${store.code}`, 0);
    const invoiceNumber = `${settings.invoicePrefix}-${store.code}-${String(seq).padStart(6, '0')}`;

    const sale = await tx.sale.create({
      data: {
        invoiceNumber,
        storeId,
        customerName: input.customerName,
        customerPhone: input.customerPhone,
        paymentMethod: input.paymentMethod as PaymentMethod,
        subtotal: subtotal.toNumber(),
        tax: tax.toNumber(),
        discount: discount.toNumber(),
        grandTotal: grandTotal.toNumber(),
        notes: input.notes,
        clientRequestId: input.clientRequestId,
        createdById: context.user.id,
        items: {
          create: lines.map((l) => ({
            product: { connect: { id: l.product.id } },
            quantity: l.quantity,
            unitPrice: l.unitPrice.toNumber(),
            discount: l.discount.toNumber(),
            taxRate: l.taxRate,
            tax: l.tax.toNumber(),
            total: l.total.toNumber(),
          })),
        },
      },
    });

    for (const l of lines) {
      await applyMovement(tx, {
        location: { kind: 'STORE', storeId },
        productId: l.product.id,
        type: MovementType.SALE,
        quantity: -l.quantity,
        referenceType: ReferenceType.SALE,
        referenceId: sale.id,
        reason: `Sale ${invoiceNumber}`,
        userId: context.user.id,
      });
    }
    await audit(tx, context, {
      action: 'CREATE',
      module: 'sales',
      recordId: sale.id,
      summary: `Recorded sale ${invoiceNumber} at ${store.name} for ${grandTotal.toFixed(2)}`,
      newValue: { invoiceNumber, grandTotal, items: lines.map((l) => ({ sku: l.product.sku, quantity: l.quantity, unitPrice: l.unitPrice })) },
    });
    return sale.id;
  });

  return { sale: await getSale(context, id), duplicate: false };
}

/** Voids a sale and returns its stock. Not allowed once returns were recorded against it. */
export async function cancelSale(context: RequestContext, id: string, reason: string) {
  await transaction(async (tx) => {
    const sale = await tx.sale.findUnique({ where: { id }, include: { items: true, _count: { select: { returns: true } } } });
    if (!sale) throw ApiError.notFound('Sale');
    assertRecordInScope(context.scope, [sale.storeId], 'Sale');
    if (sale._count.returns > 0) throw ApiError.invalidState('This sale has returns and cannot be cancelled');

    const result = await tx.sale.updateMany({
      where: { id, status: SaleStatus.COMPLETED },
      data: { status: SaleStatus.CANCELLED, cancelledAt: new Date(), cancelReason: reason },
    });
    if (!result.count) throw ApiError.invalidState('This sale is already cancelled');

    for (const item of sale.items) {
      await applyMovement(tx, {
        location: { kind: 'STORE', storeId: sale.storeId },
        productId: item.productId,
        type: MovementType.CANCELLATION,
        quantity: item.quantity,
        referenceType: ReferenceType.SALE_CANCELLATION,
        referenceId: id,
        reason: `Cancelled sale ${sale.invoiceNumber}: ${reason}`,
        userId: context.user.id,
      });
    }
    await audit(tx, context, {
      action: 'CANCEL',
      module: 'sales',
      recordId: id,
      summary: `Cancelled sale ${sale.invoiceNumber}: ${reason}`,
      oldValue: { status: sale.status },
      newValue: { status: SaleStatus.CANCELLED, reason },
    });
  });
  return getSale(context, id);
}
