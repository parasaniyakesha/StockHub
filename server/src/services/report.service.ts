import { Prisma, Role } from '@prisma/client';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { endOfDay, startOfDay } from '../utils/pagination';
import { toNumber } from '../utils/money';
import { RequestContext } from '../types/auth';
import { getSettings } from './settings.service';
import { localTs, reportStoreIds, storeSql, storeWhere } from './reportScope';
import { categoryWithDescendants } from './category.service';
import { EXPORT_LIMIT, ExportColumn } from './export.service';
import { listQuery } from '../validators/common.validator';

export const reportQuery = listQuery.extend({
  // Reports compute their full result set server-side regardless of page size
  // (see EXPORT_LIMIT) and the UI renders it as one table rather than paging
  // through it, so allow a larger page than the 200-row cap used by ordinary
  // list endpoints.
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

async function productFilterSql(q: ReportQuery, alias = 'p') {
  const parts: Prisma.Sql[] = [];
  if (q.productId) parts.push(Prisma.sql`${Prisma.raw(`${alias}.id`)} = ${q.productId}`);
  if (q.categoryId) {
    const ids = await categoryWithDescendants(q.categoryId);
    parts.push(Prisma.sql`${Prisma.raw(`${alias}."categoryId"`)} IN (${Prisma.join(ids)})`);
  }
  if (q.search) {
    const like = `%${q.search}%`;
    parts.push(Prisma.sql`(${Prisma.raw(`${alias}.name`)} ILIKE ${like} OR ${Prisma.raw(`${alias}.sku`)} ILIKE ${like})`);
  }
  return parts.length ? Prisma.join(parts, ' AND ') : Prisma.sql`TRUE`;
}

const hideCost = (context: RequestContext) => context.user.role === Role.STORE;

// ─────────────────────────── Stock reports ───────────────────────────

export async function stockReport(context: RequestContext, q: ReportQuery): Promise<Report> {
  const type = q.type ?? 'current';
  const storeIds = await reportStoreIds(context, q);
  const includeWarehouse = context.user.role === Role.ADMIN && !q.storeId && !q.managerId;
  const pf = await productFilterSql(q);

  switch (type) {
    case 'current':
    case 'low':
    case 'store':
    case 'warehouse':
    case 'damaged': {
      const low = type === 'low' ? Prisma.sql`AND x.quantity <= p."minimumStock"` : Prisma.empty;
      const damaged = type === 'damaged' ? Prisma.sql`AND x."damagedQuantity" > 0` : Prisma.empty;
      const storePart =
        type === 'warehouse'
          ? null
          : Prisma.sql`
            SELECT st.name AS location, 'STORE' AS "locationType", p.name AS product, p.sku, c.name AS category,
              x.quantity, x."reservedQuantity" AS reserved, x.quantity - x."reservedQuantity" AS available,
              x."damagedQuantity" AS damaged, p."minimumStock" AS "minimumStock"
            FROM store_stock x JOIN products p ON p.id = x."productId" JOIN categories c ON c.id = p."categoryId"
            JOIN stores st ON st.id = x."storeId"
            WHERE ${storeSql('x."storeId"', storeIds)} AND ${pf} ${low} ${damaged}`;
      const warehousePart =
        (includeWarehouse && type !== 'store') || type === 'warehouse'
          ? Prisma.sql`
            SELECT w.name AS location, 'WAREHOUSE' AS "locationType", p.name AS product, p.sku, c.name AS category,
              x.quantity, x."reservedQuantity" AS reserved, x.quantity - x."reservedQuantity" AS available,
              x."damagedQuantity" AS damaged, p."minimumStock" AS "minimumStock"
            FROM warehouse_stock x JOIN products p ON p.id = x."productId" JOIN categories c ON c.id = p."categoryId"
            JOIN warehouses w ON w.id = x."warehouseId"
            WHERE ${pf} ${low} ${damaged}`
          : null;
      if (type === 'warehouse' && context.user.role !== Role.ADMIN) throw ApiError.forbidden();
      const parts = [storePart, warehousePart].filter((p): p is Prisma.Sql => p !== null);
      const rows = await prisma.$queryRaw<Record<string, unknown>[]>`
        SELECT * FROM (${Prisma.join(parts, ' UNION ALL ')}) r ORDER BY r."locationType", r.location, r.product LIMIT ${EXPORT_LIMIT}`;
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
      const location = includeWarehouse ? Prisma.sql`(m."warehouseId" IS NOT NULL OR ${storeSql('m."storeId"', storeIds)})` : storeSql('m."storeId"', storeIds);
      const typeFilter = q.status ? Prisma.sql`AND m.type::text = ${q.status}` : Prisma.empty;
      const rows = await prisma.$queryRaw<Record<string, unknown>[]>`
        SELECT m."createdAt" AS date, COALESCE(st.name, w.name) AS location, p.name AS product, p.sku,
          m.type::text AS type, m.bucket::text AS bucket, m.quantity, m."balanceAfter" AS balance,
          m."referenceType" AS reference, m.reason, u.name AS "user"
        FROM stock_movements m JOIN products p ON p.id = m."productId" JOIN users u ON u.id = m."createdById"
        LEFT JOIN stores st ON st.id = m."storeId" LEFT JOIN warehouses w ON w.id = m."warehouseId"
        WHERE ${location} AND ${pf} AND m."createdAt" BETWEEN ${start} AND ${end} ${typeFilter}
        ORDER BY m."createdAt" DESC LIMIT ${EXPORT_LIMIT}`;
      return {
        title: 'Stock Movement',
        columns: [
          col('date', 'Date', 'datetime'),
          col('location', 'Location'),
          col('product', 'Product'),
          col('sku', 'SKU'),
          col('type', 'Type', 'status'),
          col('bucket', 'Bucket'),
          col('quantity', 'Qty', 'number'),
          col('balance', 'Balance', 'number'),
          col('reference', 'Reference'),
          col('reason', 'Reason'),
          col('user', 'User'),
        ],
        rows,
        summary: {
          movements: rows.length,
          inbound: rows.filter((r) => Number(r.quantity) > 0).reduce((a, r) => a + Number(r.quantity), 0),
          outbound: rows.filter((r) => Number(r.quantity) < 0).reduce((a, r) => a - Number(r.quantity), 0),
        },
      };
    }

    case 'returned': {
      const { start, end } = range(q);
      const rows = await prisma.$queryRaw<Record<string, unknown>[]>`
        SELECT r."createdAt" AS date, st.name AS store, r."returnNumber" AS "returnNumber", s."invoiceNumber" AS invoice,
          p.name AS product, p.sku, ri.quantity, ri.condition::text AS condition, ri.reason, ri."unitPrice" * ri.quantity AS refund
        FROM return_items ri JOIN returns r ON r.id = ri."returnId" JOIN products p ON p.id = ri."productId"
        JOIN stores st ON st.id = r."storeId" LEFT JOIN sales s ON s.id = r."saleId"
        WHERE ${storeSql('r."storeId"', storeIds)} AND ${pf} AND r."createdAt" BETWEEN ${start} AND ${end}
        ORDER BY r."createdAt" DESC LIMIT ${EXPORT_LIMIT}`;
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
          refund: rows.reduce((a, r) => a + toNumber(r.refund as Prisma.Decimal), 0),
        },
      };
    }

    case 'valuation': {
      const cost = hideCost(context) ? Prisma.sql`NULL::numeric` : Prisma.sql`SUM(x.quantity * p."purchasePrice")`;
      const storePart = Prisma.sql`
        SELECT st.name AS location, SUM(x.quantity) AS units, ${cost} AS "costValue", SUM(x.quantity * p."sellingPrice") AS "retailValue"
        FROM store_stock x JOIN products p ON p.id = x."productId" JOIN stores st ON st.id = x."storeId"
        WHERE ${storeSql('x."storeId"', storeIds)} AND ${pf} GROUP BY st.name`;
      const warehousePart = Prisma.sql`
        SELECT w.name AS location, SUM(x.quantity) AS units, ${cost} AS "costValue", SUM(x.quantity * p."sellingPrice") AS "retailValue"
        FROM warehouse_stock x JOIN products p ON p.id = x."productId" JOIN warehouses w ON w.id = x."warehouseId"
        WHERE ${pf} GROUP BY w.name`;
      const rows = await prisma.$queryRaw<Record<string, unknown>[]>`
        SELECT * FROM (${includeWarehouse ? Prisma.sql`${warehousePart} UNION ALL ${storePart}` : storePart}) r ORDER BY r.location`;
      const normalized: Record<string, unknown>[] = rows.map((r) => ({ ...r, units: Number(r.units) }));
      return {
        title: 'Stock Valuation',
        columns: [
          col('location', 'Location'),
          col('units', 'Units', 'number'),
          ...(hideCost(context) ? [] : [col('costValue', 'Cost value', 'money')]),
          col('retailValue', 'Retail value', 'money'),
        ],
        rows: normalized,
        summary: {
          units: normalized.reduce((a, r) => a + Number(r.units), 0),
          costValue: hideCost(context) ? undefined : normalized.reduce((a, r) => a + toNumber(r.costValue as Prisma.Decimal), 0),
          retailValue: normalized.reduce((a, r) => a + toNumber(r.retailValue as Prisma.Decimal), 0),
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
  const { tz } = { tz: (await getSettings()).timezone };
  const { start, end } = range(q, groupBy === 'year' ? 365 * 3 : groupBy === 'month' ? 365 : 30);
  const storeIds = await reportStoreIds(context, q);
  const pf = await productFilterSql(q);
  const base = Prisma.sql`
    FROM sale_items si JOIN sales s ON s.id = si."saleId" JOIN products p ON p.id = si."productId"
    JOIN categories c ON c.id = p."categoryId" JOIN stores st ON st.id = s."storeId"
    WHERE s.status = 'COMPLETED' AND ${storeSql('s."storeId"', storeIds)} AND ${pf}
      AND s."createdAt" BETWEEN ${start} AND ${end}`;
  const measures = Prisma.sql`
    COUNT(DISTINCT s.id) AS invoices, SUM(si.quantity) AS units,
    SUM(si.quantity * si."unitPrice") AS gross, SUM(si.discount) AS "lineDiscount", SUM(si.tax) AS tax, SUM(si.total) AS total`;

  let rows: Record<string, unknown>[];
  let first: ReportColumn[];
  if (['day', 'week', 'month', 'year'].includes(groupBy)) {
    const unit = Prisma.raw(`'${groupBy}'`);
    rows = await prisma.$queryRaw`
      SELECT date_trunc(${unit}, ${localTs('s."createdAt"', tz)})::date AS period, ${measures} ${base}
      GROUP BY 1 ORDER BY 1`;
    first = [col('period', groupBy === 'day' ? 'Date' : `${groupBy[0].toUpperCase()}${groupBy.slice(1)} starting`, 'date')];
  } else if (groupBy === 'store') {
    rows = await prisma.$queryRaw`SELECT st.code, st.name AS store, ${measures} ${base} GROUP BY st.id ORDER BY total DESC`;
    first = [col('code', 'Code'), col('store', 'Store')];
  } else if (groupBy === 'product') {
    rows = await prisma.$queryRaw`
      SELECT p.sku, p.name AS product, c.name AS category, ${measures} ${base} GROUP BY p.id, c.name ORDER BY total DESC LIMIT ${EXPORT_LIMIT}`;
    first = [col('sku', 'SKU'), col('product', 'Product'), col('category', 'Category')];
  } else {
    rows = await prisma.$queryRaw`SELECT c.code, c.name AS category, ${measures} ${base} GROUP BY c.id ORDER BY total DESC`;
    first = [col('code', 'Code'), col('category', 'Category')];
  }

  const normalized = rows.map((r) => ({ ...r, invoices: Number(r.invoices), units: Number(r.units) }));
  // Invoice-level discount is not allocated to lines; report it separately.
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
    rows: normalized,
    summary: {
      from: start,
      to: end,
      invoices: invoiceTotals._count,
      units: normalized.reduce((a, r) => a + r.units, 0),
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
  const status = q.status ? Prisma.sql`AND x.status::text = ${q.status}` : Prisma.empty;

  switch (type) {
    case 'requests': {
      const rows = await prisma.$queryRaw<Record<string, unknown>[]>`
        SELECT x."requestNumber" AS number, st.name AS store, x.status::text AS status, x."createdAt" AS created,
          x."submittedAt" AS submitted, x."reviewedAt" AS reviewed,
          COUNT(i.id) AS lines, SUM(i."requestedQuantity") AS requested, SUM(COALESCE(i."approvedQuantity",0)) AS approved
        FROM product_requests x JOIN stores st ON st.id = x."storeId" LEFT JOIN product_request_items i ON i."requestId" = x.id
        WHERE ${storeSql('x."storeId"', storeIds)} AND x."createdAt" BETWEEN ${start} AND ${end} ${status}
        GROUP BY x.id, st.name ORDER BY x."createdAt" DESC LIMIT ${EXPORT_LIMIT}`;
      return {
        title: 'Product Requests',
        columns: [
          col('number', 'Request #'), col('store', 'Store'), col('status', 'Status', 'status'), col('created', 'Created', 'datetime'),
          col('submitted', 'Submitted', 'datetime'), col('reviewed', 'Reviewed', 'datetime'), col('lines', 'Lines', 'number'),
          col('requested', 'Requested', 'number'), col('approved', 'Approved', 'number'),
        ],
        rows: rows.map((r) => ({ ...r, lines: Number(r.lines), requested: Number(r.requested ?? 0), approved: Number(r.approved ?? 0) })),
      };
    }
    case 'packing': {
      const rows = await prisma.$queryRaw<Record<string, unknown>[]>`
        SELECT x."orderNumber" AS number, st.name AS store, x.status::text AS status, ps.status::text AS "storeStatus",
          x."createdAt" AS created, x."dispatchedAt" AS dispatched, ps."receivedAt" AS received,
          SUM(i."allocatedQuantity") AS allocated, SUM(i."packedQuantity") AS packed, SUM(i."dispatchedQuantity") AS "dispatchedQty",
          SUM(i."receivedQuantity") AS "receivedQty", SUM(i."damagedQuantity") AS damaged
        FROM packing_orders x JOIN packing_order_stores ps ON ps."packingOrderId" = x.id JOIN stores st ON st.id = ps."storeId"
        LEFT JOIN packing_order_store_items i ON i."packingOrderStoreId" = ps.id
        WHERE ${storeSql('ps."storeId"', storeIds)} AND x."createdAt" BETWEEN ${start} AND ${end} ${status}
          ${context.user.role === Role.STORE ? Prisma.sql`AND x.status <> 'DRAFT'` : Prisma.empty}
        GROUP BY x.id, ps.id, st.name ORDER BY x."createdAt" DESC LIMIT ${EXPORT_LIMIT}`;
      return {
        title: 'Packing Orders',
        columns: [
          col('number', 'Order #'), col('store', 'Store'), col('status', 'Order status', 'status'), col('storeStatus', 'Store status', 'status'),
          col('created', 'Created', 'datetime'), col('dispatched', 'Dispatched', 'datetime'), col('received', 'Received', 'datetime'),
          col('allocated', 'Allocated', 'number'), col('packed', 'Packed', 'number'), col('dispatchedQty', 'Dispatched qty', 'number'),
          col('receivedQty', 'Received qty', 'number'), col('damaged', 'Damaged', 'number'),
        ],
        rows: rows.map((r) => ({
          ...r,
          allocated: Number(r.allocated ?? 0), packed: Number(r.packed ?? 0), dispatchedQty: Number(r.dispatchedQty ?? 0),
          receivedQty: Number(r.receivedQty ?? 0), damaged: Number(r.damaged ?? 0),
        })),
      };
    }
    case 'transfers': {
      const scope = storeIds === null ? Prisma.sql`TRUE` : Prisma.sql`(${storeSql('x."toStoreId"', storeIds)} OR ${storeSql('x."fromStoreId"', storeIds)})`;
      const rows = await prisma.$queryRaw<Record<string, unknown>[]>`
        SELECT x."transferNumber" AS number, COALESCE(fs.name, w.name) AS "from", ts.name AS "to", x.status::text AS status,
          x."createdAt" AS created, x."dispatchedAt" AS dispatched, x."receivedAt" AS received,
          SUM(i."requestedQuantity") AS requested, SUM(COALESCE(i."approvedQuantity",0)) AS approved,
          SUM(i."dispatchedQuantity") AS "dispatchedQty", SUM(i."receivedQuantity") AS "receivedQty"
        FROM stock_transfers x JOIN stores ts ON ts.id = x."toStoreId" LEFT JOIN stores fs ON fs.id = x."fromStoreId"
        LEFT JOIN warehouses w ON w.id = x."fromWarehouseId" LEFT JOIN stock_transfer_items i ON i."transferId" = x.id
        WHERE ${scope} AND x."createdAt" BETWEEN ${start} AND ${end} ${status}
        GROUP BY x.id, fs.name, w.name, ts.name ORDER BY x."createdAt" DESC LIMIT ${EXPORT_LIMIT}`;
      return {
        title: 'Stock Transfers',
        columns: [
          col('number', 'Transfer #'), col('from', 'From'), col('to', 'To'), col('status', 'Status', 'status'),
          col('created', 'Created', 'datetime'), col('dispatched', 'Dispatched', 'datetime'), col('received', 'Received', 'datetime'),
          col('requested', 'Requested', 'number'), col('approved', 'Approved', 'number'), col('dispatchedQty', 'Dispatched', 'number'),
          col('receivedQty', 'Received', 'number'),
        ],
        rows: rows.map((r) => ({
          ...r, requested: Number(r.requested ?? 0), approved: Number(r.approved ?? 0),
          dispatchedQty: Number(r.dispatchedQty ?? 0), receivedQty: Number(r.receivedQty ?? 0),
        })),
      };
    }
    case 'pending-receipts': {
      const rows = await prisma.$queryRaw<Record<string, unknown>[]>`
        SELECT 'PACKING_ORDER' AS kind, x."orderNumber" AS number, w.name AS "from", st.name AS "to", ps."dispatchedAt" AS dispatched,
          SUM(i."dispatchedQuantity") AS quantity
        FROM packing_order_stores ps JOIN packing_orders x ON x.id = ps."packingOrderId" JOIN stores st ON st.id = ps."storeId"
        JOIN warehouses w ON w.id = x."warehouseId" LEFT JOIN packing_order_store_items i ON i."packingOrderStoreId" = ps.id
        WHERE ps.status = 'DISPATCHED' AND ${storeSql('ps."storeId"', storeIds)}
        GROUP BY x.id, ps.id, w.name, st.name
        UNION ALL
        SELECT 'TRANSFER' AS kind, x."transferNumber", COALESCE(fs.name, w.name), ts.name, x."dispatchedAt", SUM(i."dispatchedQuantity")
        FROM stock_transfers x JOIN stores ts ON ts.id = x."toStoreId" LEFT JOIN stores fs ON fs.id = x."fromStoreId"
        LEFT JOIN warehouses w ON w.id = x."fromWarehouseId" LEFT JOIN stock_transfer_items i ON i."transferId" = x.id
        WHERE x.status = 'DISPATCHED' AND ${storeSql('x."toStoreId"', storeIds)}
        GROUP BY x.id, fs.name, w.name, ts.name
        ORDER BY dispatched ASC NULLS LAST`;
      return {
        title: 'Pending Receipts',
        columns: [col('kind', 'Type', 'status'), col('number', 'Document #'), col('from', 'From'), col('to', 'To'), col('dispatched', 'Dispatched', 'datetime'), col('quantity', 'Units in transit', 'number')],
        rows: rows.map((r) => ({ ...r, quantity: Number(r.quantity ?? 0) })),
        summary: { documents: rows.length, units: rows.reduce((a, r) => a + Number(r.quantity ?? 0), 0) },
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
  const rows = await prisma.$queryRaw<Record<string, unknown>[]>`
    SELECT st.code, st.name AS store, st.city, m.name AS manager, st.status::text AS status,
      (SELECT COUNT(*) FROM sales s WHERE s."storeId" = st.id AND s.status = 'COMPLETED' AND s."createdAt" BETWEEN ${start} AND ${end}) AS invoices,
      (SELECT COALESCE(SUM(s."grandTotal"),0) FROM sales s WHERE s."storeId" = st.id AND s.status = 'COMPLETED' AND s."createdAt" BETWEEN ${start} AND ${end}) AS revenue,
      (SELECT COALESCE(SUM(ss.quantity),0) FROM store_stock ss WHERE ss."storeId" = st.id) AS units,
      (SELECT COUNT(*) FROM store_stock ss JOIN products p ON p.id = ss."productId" WHERE ss."storeId" = st.id AND ss.quantity <= p."minimumStock") AS "lowStock",
      (SELECT COALESCE(SUM(ss."damagedQuantity"),0) FROM store_stock ss WHERE ss."storeId" = st.id) AS damaged,
      (SELECT COUNT(*) FROM product_requests r WHERE r."storeId" = st.id AND r.status IN ('SUBMITTED','UNDER_REVIEW')) AS "pendingRequests"
    FROM stores st LEFT JOIN users m ON m.id = st."assignedManagerId"
    WHERE ${storeSql('st.id', storeIds)}
    ORDER BY revenue DESC`;
  const normalized: Record<string, unknown>[] = rows.map((r) => ({
    ...r,
    invoices: Number(r.invoices), units: Number(r.units), lowStock: Number(r.lowStock), damaged: Number(r.damaged), pendingRequests: Number(r.pendingRequests),
  }));
  return {
    title: 'Store Performance',
    columns: [
      col('code', 'Code'), col('store', 'Store'), col('city', 'City'), col('manager', 'Manager'), col('status', 'Status', 'status'),
      col('invoices', 'Invoices', 'number'), col('revenue', 'Revenue', 'money'), col('units', 'Units in stock', 'number'),
      col('lowStock', 'Low-stock lines', 'number'), col('damaged', 'Damaged', 'number'), col('pendingRequests', 'Pending requests', 'number'),
    ],
    rows: normalized,
    summary: { from: start, to: end, stores: normalized.length, revenue: normalized.reduce((a, r) => a + toNumber(r.revenue as Prisma.Decimal), 0) },
  };
}

/** Converts a report into export columns. */
export function exportColumns(report: Report): ExportColumn<Record<string, unknown>>[] {
  return report.columns.map((c) => ({
    header: c.label,
    numeric: c.type === 'number' || c.type === 'money',
    width: c.type === 'datetime' ? 20 : c.type === 'number' || c.type === 'money' ? 12 : 18,
    value: (row) => {
      const v = row[c.key];
      if (v === null || v === undefined) return '';
      if (c.type === 'money') return toNumber(v as Prisma.Decimal).toFixed(2);
      if (c.type === 'date' && v instanceof Date) return v.toISOString().slice(0, 10);
      if (v instanceof Date) return v;
      if (typeof v === 'object' && 'toNumber' in (v as object)) return (v as Prisma.Decimal).toNumber();
      return v as string | number;
    },
  }));
}
