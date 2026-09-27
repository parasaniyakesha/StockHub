import { Prisma, Role } from '@prisma/client';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { endOfDay, startOfDay } from '../utils/pagination';
import { toNumber } from '../utils/money';
import { RequestContext } from '../types/auth';
import { reportStoreIds, storeWhere } from './reportScope';
import { categoryWithDescendants } from './category.service';
import { EXPORT_LIMIT, ExportColumn } from './export.service';
import { listQuery } from '../validators/common.validator';

export const reportQuery = listQuery.extend({
  limit: z.coerce.number().int().min(1).max(1000).default(20),
  type: z.string().trim().max(40).optional(),
  groupBy: z.enum(['day', 'week', 'month', 'year', 'store', 'product', 'category']).optional(),
  format: z.enum(['json', 'csv', 'xlsx', 'pdf']).default('json'),
});
export type ReportQuery = z.infer<typeof reportQuery>;

export interface ReportColumn {
  key: string;
  label: string;
  type?: 'text' | 'number' | 'money' | 'date' | 'datetime' | 'status';
}

export interface Report {
  title: string;
  columns: ReportColumn[];
  rows: Record<string, unknown>[];
  summary?: Record<string, unknown>;
}

const col = (key: string, label: string, type: ReportColumn['type'] = 'text'): ReportColumn => ({ key, label, type });

function range(q: ReportQuery, defaultDays = 30) {
  const end = q.endDate ? endOfDay(q.endDate) : endOfDay(new Date());
  const start = q.startDate ? startOfDay(q.startDate) : startOfDay(new Date(end.getTime() - (defaultDays - 1) * 86_400_000));
  if (start > end) throw ApiError.validation([{ field: 'startDate', message: 'Start date must be before end date' }]);
  return { start, end };
}

async function productWhereInput(q: ReportQuery): Promise<Prisma.ProductWhereInput> {
  const where: Prisma.ProductWhereInput = {};
  if (q.productId) where.id = q.productId;
  if (q.categoryId) {
    const ids = await categoryWithDescendants(q.categoryId);
    where.categoryId = { in: ids };
  }
  if (q.search) {
    where.OR = [
      { name: { contains: q.search, mode: 'insensitive' } },
      { sku: { contains: q.search, mode: 'insensitive' } },
    ];
  }
  return where;
}

const hideCost = (context: RequestContext) => context.user.role === Role.STORE;

// ─────────────────────────── Stock reports ───────────────────────────

export async function stockReport(context: RequestContext, q: ReportQuery): Promise<Report> {
  const type = q.type ?? 'current';
  const storeIds = await reportStoreIds(context, q);
  const includeWarehouse = context.user.role === Role.ADMIN && !q.storeId && !q.managerId;
  const pWhere = await productWhereInput(q);

  switch (type) {
    case 'current':
    case 'low':
    case 'store':
    case 'warehouse':
    case 'damaged': {
      let storeRows: Record<string, unknown>[] = [];
      if (type !== 'warehouse') {
        const storeStock = await prisma.storeStock.findMany({
          where: {
            ...storeWhere(storeIds),
            product: pWhere,
            ...(type === 'damaged' ? { damagedQuantity: { gt: 0 } } : {}),
          },
          include: {
            store: { select: { name: true } },
            product: { select: { name: true, sku: true, minimumStock: true, category: { select: { name: true } } } },
          },
          take: EXPORT_LIMIT,
        });
        storeRows = storeStock
          .filter((x) => type !== 'low' || x.quantity <= x.product.minimumStock)
          .map((x) => ({
            location: x.store.name,
            locationType: 'STORE',
            product: x.product.name,
            sku: x.product.sku,
            category: x.product.category.name,
            quantity: x.quantity,
            reserved: x.reservedQuantity,
            available: x.quantity - x.reservedQuantity,
            damaged: x.damagedQuantity,
            minimumStock: x.product.minimumStock,
          }));
      }

      let warehouseRows: Record<string, unknown>[] = [];
      if ((includeWarehouse && type !== 'store') || type === 'warehouse') {
        const whStock = await prisma.warehouseStock.findMany({
          where: {
            product: pWhere,
            ...(type === 'damaged' ? { damagedQuantity: { gt: 0 } } : {}),
          },
          include: {
            warehouse: { select: { name: true } },
            product: { select: { name: true, sku: true, minimumStock: true, category: { select: { name: true } } } },
          },
          take: EXPORT_LIMIT,
        });
        warehouseRows = whStock
          .filter((x) => type !== 'low' || x.quantity <= x.product.minimumStock)
          .map((x) => ({
            location: x.warehouse.name,
            locationType: 'WAREHOUSE',
            product: x.product.name,
            sku: x.product.sku,
            category: x.product.category.name,
            quantity: x.quantity,
            reserved: x.reservedQuantity,
            available: x.quantity - x.reservedQuantity,
            damaged: x.damagedQuantity,
            minimumStock: x.product.minimumStock,
          }));
      }

      const rows = [...storeRows, ...warehouseRows].slice(0, EXPORT_LIMIT);
      const titles: Record<string, string> = {
        current: 'Current Stock',
        low: 'Low Stock',
        store: 'Store Stock',
        warehouse: 'Warehouse Stock',
        damaged: 'Damaged Stock',
      };
      return {
        title: titles[type],
        columns: [
          col('location', 'Location'),
          col('product', 'Product'),
          col('sku', 'SKU'),
          col('category', 'Category'),
          col('quantity', 'On hand', 'number'),
          col('reserved', 'Reserved', 'number'),
          col('available', 'Available', 'number'),
          col('damaged', 'Damaged', 'number'),
          col('minimumStock', 'Min', 'number'),
        ],
        rows,
        summary: {
          lines: rows.length,
          onHand: rows.reduce((a, r) => a + Number(r.quantity), 0),
          damaged: rows.reduce((a, r) => a + Number(r.damaged), 0),
        },
      };
    }

    case 'movement': {
      const { start, end } = range(q);
      const movements = await prisma.stockMovement.findMany({
        where: {
          createdAt: { gte: start, lte: end },
          product: pWhere,
          ...(q.status ? { type: q.status as any } : {}),
          ...(includeWarehouse
            ? storeIds ? { OR: [{ warehouseId: { not: null } }, { storeId: { in: storeIds } }] } : {}
            : storeIds ? { storeId: { in: storeIds } } : { storeId: { not: null } }),
        },
        include: {
          product: { select: { name: true, sku: true } },
          store: { select: { name: true } },
          warehouse: { select: { name: true } },
          createdBy: { select: { name: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: EXPORT_LIMIT,
      });
      const rows = movements.map((m) => ({
        date: m.createdAt,
        location: m.store?.name ?? m.warehouse?.name ?? 'Unknown',
        product: m.product.name,
        sku: m.product.sku,
        type: String(m.type),
        bucket: String(m.bucket),
        quantity: m.quantity,
        balance: m.balanceAfter,
        reference: m.referenceType,
        reason: m.reason,
        user: m.createdBy.name,
      }));
      return {
        title: 'Stock Movements',
        columns: [
          col('date', 'Date', 'datetime'),
          col('location', 'Location'),
          col('product', 'Product'),
          col('sku', 'SKU'),
          col('type', 'Type', 'status'),
          col('bucket', 'Bucket', 'status'),
          col('quantity', 'Quantity', 'number'),
          col('balance', 'Balance after', 'number'),
          col('reference', 'Reference'),
          col('reason', 'Reason'),
          col('user', 'Recorded by'),
        ],
        rows,
        summary: {
          movements: rows.length,
          netQuantity: rows.reduce((a, r) => a + Number(r.quantity), 0),
        },
      };
    }

    case 'returns': {
      const { start, end } = range(q);
      const returnItems = await prisma.saleReturnItem.findMany({
        where: {
          saleReturn: {
            createdAt: { gte: start, lte: end },
            ...(storeIds ? { storeId: { in: storeIds } } : {}),
          },
          product: pWhere,
        },
        include: {
          saleReturn: {
            include: {
              store: { select: { name: true } },
              sale: { select: { invoiceNumber: true } },
            },
          },
          product: { select: { name: true, sku: true } },
        },
        orderBy: { saleReturn: { createdAt: 'desc' } },
        take: EXPORT_LIMIT,
      });
      const rows = returnItems.map((ri) => ({
        date: ri.saleReturn.createdAt,
        store: ri.saleReturn.store.name,
        returnNumber: ri.saleReturn.returnNumber,
        invoice: ri.saleReturn.sale?.invoiceNumber ?? '',
        product: ri.product.name,
        sku: ri.product.sku,
        quantity: ri.quantity,
        condition: String(ri.condition),
        reason: ri.reason,
        refund: Number(ri.unitPrice) * ri.quantity,
      }));
      return {
        title: 'Returned Stock',
        columns: [
          col('date', 'Date', 'datetime'),
          col('store', 'Store'),
          col('returnNumber', 'Return #'),
          col('invoice', 'Invoice'),
          col('product', 'Product'),
          col('sku', 'SKU'),
          col('quantity', 'Qty', 'number'),
          col('condition', 'Condition', 'status'),
          col('reason', 'Reason'),
          col('refund', 'Refund', 'money'),
        ],
        rows,
        summary: {
          units: rows.reduce((a, r) => a + Number(r.quantity), 0),
          damaged: rows.filter((r) => r.condition === 'DAMAGED').reduce((a, r) => a + Number(r.quantity), 0),
          refund: rows.reduce((a, r) => a + Number(r.refund), 0),
        },
      };
    }

    case 'valuation': {
      const isCostHidden = hideCost(context);
      const storeStock = await prisma.storeStock.findMany({
        where: {
          ...storeWhere(storeIds),
          product: pWhere,
        },
        include: {
          store: { select: { name: true } },
          product: { select: { purchasePrice: true, sellingPrice: true } },
        },
      });

      const storeMap = new Map<string, { location: string; units: number; costValue: number; retailValue: number }>();
      for (const item of storeStock) {
        const loc = item.store.name;
        const entry = storeMap.get(loc) ?? { location: loc, units: 0, costValue: 0, retailValue: 0 };
        entry.units += item.quantity;
        entry.costValue += item.quantity * Number(item.product.purchasePrice);
        entry.retailValue += item.quantity * Number(item.product.sellingPrice);
        storeMap.set(loc, entry);
      }

      if (includeWarehouse) {
        const whStock = await prisma.warehouseStock.findMany({
          where: { product: pWhere },
          include: {
            warehouse: { select: { name: true } },
            product: { select: { purchasePrice: true, sellingPrice: true } },
          },
        });
        for (const item of whStock) {
          const loc = item.warehouse.name;
          const entry = storeMap.get(loc) ?? { location: loc, units: 0, costValue: 0, retailValue: 0 };
          entry.units += item.quantity;
          entry.costValue += item.quantity * Number(item.product.purchasePrice);
          entry.retailValue += item.quantity * Number(item.product.sellingPrice);
          storeMap.set(loc, entry);
        }
      }

      const rows = Array.from(storeMap.values()).sort((a, b) => a.location.localeCompare(b.location));
      return {
        title: 'Stock Valuation',
        columns: [
          col('location', 'Location'),
          col('units', 'Units', 'number'),
          ...(isCostHidden ? [] : [col('costValue', 'Cost value', 'money')]),
          col('retailValue', 'Retail value', 'money'),
        ],
        rows,
        summary: {
          units: rows.reduce((a, r) => a + Number(r.units), 0),
          costValue: isCostHidden ? undefined : rows.reduce((a, r) => a + Number(r.costValue), 0),
          retailValue: rows.reduce((a, r) => a + Number(r.retailValue), 0),
        },
      };
    }
    default:
      throw ApiError.badRequest(`Unknown stock report "${type}"`);
  }
}

// ─────────────────────────── Sales reports ───────────────────────────

export async function salesReport(context: RequestContext, q: ReportQuery): Promise<Report> {
  const groupBy = q.groupBy ?? 'day';
  const { start, end } = range(q, groupBy === 'year' ? 365 * 3 : groupBy === 'month' ? 365 : 30);
  const storeIds = await reportStoreIds(context, q);
  const pWhere = await productWhereInput(q);

  const saleItems = await prisma.saleItem.findMany({
    where: {
      sale: {
        status: 'COMPLETED',
        createdAt: { gte: start, lte: end },
        ...storeWhere(storeIds),
      },
      product: pWhere,
    },
    include: {
      sale: { select: { id: true, createdAt: true, storeId: true, store: { select: { code: true, name: true } } } },
      product: { select: { id: true, sku: true, name: true, category: { select: { id: true, code: true, name: true } } } },
    },
  });

  type Bucket = {
    key: string;
    label1: string;
    label2?: string;
    label3?: string;
    invoices: Set<string>;
    units: number;
    gross: number;
    lineDiscount: number;
    tax: number;
    total: number;
  };
  const buckets = new Map<string, Bucket>();

  for (const item of saleItems) {
    let bKey = '';
    let l1 = '';
    let l2: string | undefined;
    let l3: string | undefined;

    const d = item.sale.createdAt;
    if (groupBy === 'day') {
      bKey = d.toISOString().slice(0, 10);
      l1 = bKey;
    } else if (groupBy === 'week') {
      const firstDay = new Date(d);
      firstDay.setDate(d.getDate() - d.getDay());
      bKey = firstDay.toISOString().slice(0, 10);
      l1 = bKey;
    } else if (groupBy === 'month') {
      bKey = d.toISOString().slice(0, 7);
      l1 = bKey;
    } else if (groupBy === 'year') {
      bKey = d.toISOString().slice(0, 4);
      l1 = bKey;
    } else if (groupBy === 'store') {
      bKey = item.sale.storeId;
      l1 = item.sale.store.code;
      l2 = item.sale.store.name;
    } else if (groupBy === 'product') {
      bKey = item.productId;
      l1 = item.product.sku;
      l2 = item.product.name;
      l3 = item.product.category.name;
    } else {
      bKey = item.product.category.id;
      l1 = item.product.category.code;
      l2 = item.product.category.name;
    }

    const b = buckets.get(bKey) ?? {
      key: bKey,
      label1: l1,
      label2: l2,
      label3: l3,
      invoices: new Set<string>(),
      units: 0,
      gross: 0,
      lineDiscount: 0,
      tax: 0,
      total: 0,
    };
    b.invoices.add(item.sale.id);
    b.units += item.quantity;
    b.gross += item.quantity * Number(item.unitPrice);
    b.lineDiscount += Number(item.discount);
    b.tax += Number(item.tax);
    b.total += Number(item.total);
    buckets.set(bKey, b);
  }

  let first: ReportColumn[];
  let rows: Record<string, unknown>[];
  if (['day', 'week', 'month', 'year'].includes(groupBy)) {
    first = [col('period', groupBy === 'day' ? 'Date' : `${groupBy[0].toUpperCase()}${groupBy.slice(1)} starting`, 'date')];
    rows = Array.from(buckets.values())
      .sort((a, b) => a.key.localeCompare(b.key))
      .map((b) => ({
        period: b.label1,
        invoices: b.invoices.size,
        units: b.units,
        gross: b.gross,
        lineDiscount: b.lineDiscount,
        tax: b.tax,
        total: b.total,
      }));
  } else if (groupBy === 'store') {
    first = [col('code', 'Code'), col('store', 'Store')];
    rows = Array.from(buckets.values())
      .sort((a, b) => b.total - a.total)
      .map((b) => ({
        code: b.label1,
        store: b.label2,
        invoices: b.invoices.size,
        units: b.units,
        gross: b.gross,
        lineDiscount: b.lineDiscount,
        tax: b.tax,
        total: b.total,
      }));
  } else if (groupBy === 'product') {
    first = [col('sku', 'SKU'), col('product', 'Product'), col('category', 'Category')];
    rows = Array.from(buckets.values())
      .sort((a, b) => b.total - a.total)
      .slice(0, EXPORT_LIMIT)
      .map((b) => ({
        sku: b.label1,
        product: b.label2,
        category: b.label3,
        invoices: b.invoices.size,
        units: b.units,
        gross: b.gross,
        lineDiscount: b.lineDiscount,
        tax: b.tax,
        total: b.total,
      }));
  } else {
    first = [col('code', 'Code'), col('category', 'Category')];
    rows = Array.from(buckets.values())
      .sort((a, b) => b.total - a.total)
      .map((b) => ({
        code: b.label1,
        category: b.label2,
        invoices: b.invoices.size,
        units: b.units,
        gross: b.gross,
        lineDiscount: b.lineDiscount,
        tax: b.tax,
        total: b.total,
      }));
  }

  const invoiceTotals = await prisma.sale.aggregate({
    where: { status: 'COMPLETED', ...storeWhere(storeIds), createdAt: { gte: start, lte: end } },
    _sum: { grandTotal: true, discount: true },
    _count: true,
  });

  const titles: Record<string, string> = {
    day: 'Daily Sales',
    week: 'Weekly Sales',
    month: 'Monthly Sales',
    year: 'Yearly Sales',
    store: 'Store-wise Sales',
    product: 'Product-wise Sales',
    category: 'Category-wise Sales',
  };

  return {
    title: titles[groupBy],
    columns: [
      ...first,
      col('invoices', 'Invoices', 'number'),
      col('units', 'Units', 'number'),
      col('gross', 'Gross', 'money'),
      col('lineDiscount', 'Line discount', 'money'),
      col('tax', 'Tax', 'money'),
      col('total', 'Line total', 'money'),
    ],
    rows,
    summary: {
      from: start,
      to: end,
      invoices: invoiceTotals._count,
      units: rows.reduce((a, r) => a + Number(r.units), 0),
      invoiceDiscount: invoiceTotals._sum.discount ?? 0,
      netSales: invoiceTotals._sum.grandTotal ?? 0,
    },
  };
}

// ─────────────────────────── Operations reports ───────────────────────────

export async function operationsReport(context: RequestContext, q: ReportQuery): Promise<Report> {
  const type = q.type ?? 'requests';
  const { start, end } = range(q, 90);
  const storeIds = await reportStoreIds(context, q);

  switch (type) {
    case 'requests': {
      const requests = await prisma.productRequest.findMany({
        where: {
          ...storeWhere(storeIds),
          createdAt: { gte: start, lte: end },
          ...(q.status ? { status: q.status as any } : {}),
        },
        include: {
          store: { select: { name: true } },
          items: { select: { requestedQuantity: true, approvedQuantity: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: EXPORT_LIMIT,
      });

      const rows = requests.map((x) => ({
        number: x.requestNumber,
        store: x.store.name,
        status: String(x.status),
        created: x.createdAt,
        submitted: x.submittedAt,
        reviewed: x.reviewedAt,
        lines: x.items.length,
        requested: x.items.reduce((sum, i) => sum + i.requestedQuantity, 0),
        approved: x.items.reduce((sum, i) => sum + (i.approvedQuantity ?? 0), 0),
      }));

      return {
        title: 'Product Requests',
        columns: [
          col('number', 'Request #'),
          col('store', 'Store'),
          col('status', 'Status', 'status'),
          col('created', 'Created', 'datetime'),
          col('submitted', 'Submitted', 'datetime'),
          col('reviewed', 'Reviewed', 'datetime'),
          col('lines', 'Lines', 'number'),
          col('requested', 'Requested', 'number'),
          col('approved', 'Approved', 'number'),
        ],
        rows,
      };
    }

    case 'packing': {
      const packingStores = await prisma.packingOrderStore.findMany({
        where: {
          ...storeWhere(storeIds),
          packingOrder: {
            createdAt: { gte: start, lte: end },
            ...(q.status ? { status: q.status as any } : {}),
            ...(context.user.role === Role.STORE ? { status: { not: 'DRAFT' } } : {}),
          },
        },
        include: {
          packingOrder: { select: { orderNumber: true, status: true, createdAt: true, dispatchedAt: true } },
          store: { select: { name: true } },
          items: { select: { allocatedQuantity: true, packedQuantity: true, dispatchedQuantity: true, receivedQuantity: true, damagedQuantity: true } },
        },
        orderBy: { packingOrder: { createdAt: 'desc' } },
        take: EXPORT_LIMIT,
      });

      const rows = packingStores.map((ps) => ({
        number: ps.packingOrder.orderNumber,
        store: ps.store.name,
        status: String(ps.packingOrder.status),
        storeStatus: String(ps.status),
        created: ps.packingOrder.createdAt,
        dispatched: ps.packingOrder.dispatchedAt,
        received: ps.receivedAt,
        allocated: ps.items.reduce((sum, i) => sum + i.allocatedQuantity, 0),
        packed: ps.items.reduce((sum, i) => sum + i.packedQuantity, 0),
        dispatchedQty: ps.items.reduce((sum, i) => sum + i.dispatchedQuantity, 0),
        receivedQty: ps.items.reduce((sum, i) => sum + i.receivedQuantity, 0),
        damaged: ps.items.reduce((sum, i) => sum + i.damagedQuantity, 0),
      }));

      return {
        title: 'Packing Orders',
        columns: [
          col('number', 'Order #'),
          col('store', 'Store'),
          col('status', 'Order status', 'status'),
          col('storeStatus', 'Store status', 'status'),
          col('created', 'Created', 'datetime'),
          col('dispatched', 'Dispatched', 'datetime'),
          col('received', 'Received', 'datetime'),
          col('allocated', 'Allocated', 'number'),
          col('packed', 'Packed', 'number'),
          col('dispatchedQty', 'Dispatched qty', 'number'),
          col('receivedQty', 'Received qty', 'number'),
          col('damaged', 'Damaged', 'number'),
        ],
        rows,
      };
    }

    case 'transfers': {
      const transfers = await prisma.stockTransfer.findMany({
        where: {
          createdAt: { gte: start, lte: end },
          ...(q.status ? { status: q.status as any } : {}),
          ...(storeIds ? { OR: [{ toStoreId: { in: storeIds } }, { fromStoreId: { in: storeIds } }] } : {}),
        },
        include: {
          fromStore: { select: { name: true } },
          fromWarehouse: { select: { name: true } },
          toStore: { select: { name: true } },
          items: { select: { requestedQuantity: true, approvedQuantity: true, dispatchedQuantity: true, receivedQuantity: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: EXPORT_LIMIT,
      });

      const rows = transfers.map((x) => ({
        number: x.transferNumber,
        from: x.fromStore?.name ?? x.fromWarehouse?.name ?? 'Central warehouse',
        to: x.toStore.name,
        status: String(x.status),
        created: x.createdAt,
        dispatched: x.dispatchedAt,
        received: x.receivedAt,
        requested: x.items.reduce((sum, i) => sum + i.requestedQuantity, 0),
        approved: x.items.reduce((sum, i) => sum + (i.approvedQuantity ?? 0), 0),
        dispatchedQty: x.items.reduce((sum, i) => sum + i.dispatchedQuantity, 0),
        receivedQty: x.items.reduce((sum, i) => sum + i.receivedQuantity, 0),
      }));

      return {
        title: 'Stock Transfers',
        columns: [
          col('number', 'Transfer #'),
          col('from', 'From'),
          col('to', 'To'),
          col('status', 'Status', 'status'),
          col('created', 'Created', 'datetime'),
          col('dispatched', 'Dispatched', 'datetime'),
          col('received', 'Received', 'datetime'),
          col('requested', 'Requested', 'number'),
          col('approved', 'Approved', 'number'),
          col('dispatchedQty', 'Dispatched', 'number'),
          col('receivedQty', 'Received', 'number'),
        ],
        rows,
      };
    }

    case 'pending-receipts': {
      const pendingPacking = await prisma.packingOrderStore.findMany({
        where: {
          status: 'DISPATCHED',
          ...storeWhere(storeIds),
        },
        include: {
          packingOrder: { include: { warehouse: { select: { name: true } } } },
          store: { select: { name: true } },
          items: { select: { dispatchedQuantity: true } },
        },
      });

      const packingRows = pendingPacking.map((ps) => ({
        kind: 'PACKING_ORDER',
        number: ps.packingOrder.orderNumber,
        from: ps.packingOrder.warehouse.name,
        to: ps.store.name,
        dispatched: ps.dispatchedAt,
        quantity: ps.items.reduce((sum, i) => sum + i.dispatchedQuantity, 0),
      }));

      const pendingTransfers = await prisma.stockTransfer.findMany({
        where: {
          status: 'DISPATCHED',
          ...(storeIds ? { toStoreId: { in: storeIds } } : {}),
        },
        include: {
          fromStore: { select: { name: true } },
          fromWarehouse: { select: { name: true } },
          toStore: { select: { name: true } },
          items: { select: { dispatchedQuantity: true } },
        },
      });

      const transferRows = pendingTransfers.map((t) => ({
        kind: 'TRANSFER',
        number: t.transferNumber,
        from: t.fromStore?.name ?? t.fromWarehouse?.name ?? '',
        to: t.toStore.name,
        dispatched: t.dispatchedAt,
        quantity: t.items.reduce((sum, i) => sum + i.dispatchedQuantity, 0),
      }));

      const rows = [...packingRows, ...transferRows].sort((a, b) => {
        const da = a.dispatched ? new Date(a.dispatched).getTime() : 0;
        const db = b.dispatched ? new Date(b.dispatched).getTime() : 0;
        return da - db;
      });

      return {
        title: 'Pending Receipts',
        columns: [
          col('kind', 'Type', 'status'),
          col('number', 'Document #'),
          col('from', 'From'),
          col('to', 'To'),
          col('dispatched', 'Dispatched', 'datetime'),
          col('quantity', 'Units in transit', 'number'),
        ],
        rows,
        summary: { documents: rows.length, units: rows.reduce((a, r) => a + Number(r.quantity), 0) },
      };
    }
    default:
      throw ApiError.badRequest(`Unknown operations report "${type}"`);
  }
}

// ─────────────────────────── Store performance ───────────────────────────

export async function storesReport(context: RequestContext, q: ReportQuery): Promise<Report> {
  const { start, end } = range(q);
  const storeIds = await reportStoreIds(context, q);

  const stores = await prisma.store.findMany({
    where: storeIds ? { id: { in: storeIds } } : {},
    include: {
      assignedManager: { select: { name: true } },
      stock: {
        include: {
          product: { select: { minimumStock: true } },
        },
      },
      sales: {
        where: { status: 'COMPLETED', createdAt: { gte: start, lte: end } },
        select: { grandTotal: true },
      },
      productRequests: {
        where: { status: { in: ['SUBMITTED', 'UNDER_REVIEW'] } },
        select: { id: true },
      },
    },
  });

  const normalized = stores.map((st) => {
    const invoices = st.sales.length;
    const revenue = st.sales.reduce((sum, s) => sum + Number(s.grandTotal), 0);
    const units = st.stock.reduce((sum, s) => sum + s.quantity, 0);
    const lowStock = st.stock.filter((s) => s.quantity <= s.product.minimumStock).length;
    const damaged = st.stock.reduce((sum, s) => sum + s.damagedQuantity, 0);
    const pendingRequests = st.productRequests.length;

    return {
      code: st.code,
      store: st.name,
      city: st.city ?? '',
      manager: st.assignedManager?.name ?? '',
      status: String(st.status),
      invoices,
      revenue,
      units,
      lowStock,
      damaged,
      pendingRequests,
    };
  }).sort((a, b) => b.revenue - a.revenue);

  return {
    title: 'Store Performance',
    columns: [
      col('code', 'Code'),
      col('store', 'Store'),
      col('city', 'City'),
      col('manager', 'Manager'),
      col('status', 'Status', 'status'),
      col('invoices', 'Invoices', 'number'),
      col('revenue', 'Revenue', 'money'),
      col('units', 'Units in stock', 'number'),
      col('lowStock', 'Low-stock lines', 'number'),
      col('damaged', 'Damaged', 'number'),
      col('pendingRequests', 'Pending requests', 'number'),
    ],
    rows: normalized,
    summary: {
      from: start,
      to: end,
      stores: normalized.length,
      revenue: normalized.reduce((a, r) => a + Number(r.revenue), 0),
    },
  };
}

/** Converts a report into export columns. */
export function exportColumns(report: Report): ExportColumn<Record<string, unknown>>[] {
  return report.columns.map((c) => ({
    header: c.label,
    width: c.type === 'money' || c.type === 'number' ? 14 : c.type === 'datetime' ? 22 : 18,
    numeric: c.type === 'money' || c.type === 'number',
    value: (r: Record<string, unknown>) => {
      const v = r[c.key];
      if (v === null || v === undefined) return '';
      if (v instanceof Date) return v;
      if (c.type === 'money') return Number(v).toFixed(2);
      if (typeof v === 'object' && 'toNumber' in (v as object)) return (v as Prisma.Decimal).toNumber();
      return v as string | number;
    },
  }));
}
