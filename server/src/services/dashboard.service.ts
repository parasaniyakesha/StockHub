import { PackingOrderStatus, Prisma, ProductRequestStatus, RecordStatus, Role, TransferStatus } from '@prisma/client';
import { prisma } from '../utils/prisma';
import { RequestContext } from '../types/auth';
import { getSettings } from './settings.service';
import { localTs, reportStoreIds, storeSql, storeWhere } from './reportScope';

const PENDING_REQUESTS: ProductRequestStatus[] = [ProductRequestStatus.SUBMITTED, ProductRequestStatus.UNDER_REVIEW];
const OPEN_PACKING: PackingOrderStatus[] = [
  PackingOrderStatus.DRAFT,
  PackingOrderStatus.ASSIGNED,
  PackingOrderStatus.PACKING,
  PackingOrderStatus.PACKED,
  PackingOrderStatus.DISPATCHED,
];
const OPEN_TRANSFERS: TransferStatus[] = [TransferStatus.REQUESTED, TransferStatus.APPROVED, TransferStatus.DISPATCHED];

/** Role-aware dashboard: admin = company-wide, manager = assigned stores, store = own store. */
export async function getDashboard(context: RequestContext, q: { storeId?: string }) {
  const settings = await getSettings();
  const tz = settings.timezone;
  const storeIds = await reportStoreIds(context, q);
  const isAdmin = context.user.role === Role.ADMIN && !q.storeId;
  const saleStores = storeSql('s."storeId"', storeIds);

  const [salesToday, salesMonth, trend, storeSales, topProducts, movementTrend] = await Promise.all([
    prisma.$queryRaw<{ total: Prisma.Decimal | null; count: bigint }[]>`
      SELECT COALESCE(SUM(s."grandTotal"),0) AS total, COUNT(*) AS count FROM sales s
      WHERE s.status = 'COMPLETED' AND ${saleStores}
        AND ${localTs('s."createdAt"', tz)}::date = (now() AT TIME ZONE ${tz})::date`,
    prisma.$queryRaw<{ total: Prisma.Decimal | null; count: bigint }[]>`
      SELECT COALESCE(SUM(s."grandTotal"),0) AS total, COUNT(*) AS count FROM sales s
      WHERE s.status = 'COMPLETED' AND ${saleStores}
        AND date_trunc('month', ${localTs('s."createdAt"', tz)}) = date_trunc('month', now() AT TIME ZONE ${tz})`,
    prisma.$queryRaw<{ day: Date; total: Prisma.Decimal; count: bigint }[]>`
      SELECT d.day::date AS day, COALESCE(SUM(s."grandTotal"),0) AS total, COUNT(s.id) AS count
      FROM generate_series((now() AT TIME ZONE ${tz})::date - 29, (now() AT TIME ZONE ${tz})::date, interval '1 day') AS d(day)
      LEFT JOIN sales s ON ${localTs('s."createdAt"', tz)}::date = d.day::date AND s.status = 'COMPLETED' AND ${saleStores}
      GROUP BY d.day ORDER BY d.day`,
    prisma.$queryRaw<{ storeId: string; name: string; total: Prisma.Decimal; count: bigint }[]>`
      SELECT st.id AS "storeId", st.name, COALESCE(SUM(s."grandTotal"),0) AS total, COUNT(s.id) AS count
      FROM sales s JOIN stores st ON st.id = s."storeId"
      WHERE s.status = 'COMPLETED' AND ${saleStores}
        AND date_trunc('month', ${localTs('s."createdAt"', tz)}) = date_trunc('month', now() AT TIME ZONE ${tz})
      GROUP BY st.id, st.name ORDER BY total DESC LIMIT 10`,
    prisma.$queryRaw<{ productId: string; name: string; sku: string; quantity: bigint; total: Prisma.Decimal }[]>`
      SELECT p.id AS "productId", p.name, p.sku, SUM(si.quantity) AS quantity, SUM(si.total) AS total
      FROM sale_items si JOIN sales s ON s.id = si."saleId" JOIN products p ON p.id = si."productId"
      WHERE s.status = 'COMPLETED' AND ${saleStores}
        AND ${localTs('s."createdAt"', tz)} >= (now() AT TIME ZONE ${tz}) - interval '30 days'
      GROUP BY p.id, p.name, p.sku ORDER BY quantity DESC LIMIT 10`,
    prisma.$queryRaw<{ day: Date; inbound: bigint; outbound: bigint }[]>`
      SELECT d.day::date AS day,
        COALESCE(SUM(CASE WHEN m.quantity > 0 THEN m.quantity END),0) AS inbound,
        COALESCE(SUM(CASE WHEN m.quantity < 0 THEN -m.quantity END),0) AS outbound
      FROM generate_series((now() AT TIME ZONE ${tz})::date - 13, (now() AT TIME ZONE ${tz})::date, interval '1 day') AS d(day)
      LEFT JOIN stock_movements m ON ${localTs('m."createdAt"', tz)}::date = d.day::date AND m.bucket = 'AVAILABLE'
        AND ${isAdmin ? Prisma.sql`TRUE` : storeSql('m."storeId"', storeIds)}
      GROUP BY d.day ORDER BY d.day`,
  ]);

  const storeStockWhere = storeWhere(storeIds);
  const [storeUnits, warehouseUnits, lowStoreRows, lowWarehouse, pendingRequests, packing, transfers, stores, products] = await Promise.all([
    prisma.storeStock.aggregate({ where: storeStockWhere, _sum: { quantity: true, damagedQuantity: true } }),
    isAdmin ? prisma.warehouseStock.aggregate({ _sum: { quantity: true, reservedQuantity: true } }) : Promise.resolve(null),
    prisma.$queryRaw<{ storeId: string; storeName: string; productId: string; name: string; sku: string; quantity: number; minimumStock: number }[]>`
      SELECT st.id AS "storeId", st.name AS "storeName", p.id AS "productId", p.name, p.sku, ss.quantity, p."minimumStock"
      FROM store_stock ss JOIN products p ON p.id = ss."productId" JOIN stores st ON st.id = ss."storeId"
      WHERE p.status = 'ACTIVE' AND st.status = 'ACTIVE' AND ss.quantity <= p."minimumStock" AND ${storeSql('ss."storeId"', storeIds)}
      ORDER BY (ss.quantity - p."minimumStock") ASC LIMIT 200`,
    isAdmin
      ? prisma.$queryRaw<{ productId: string; name: string; sku: string; quantity: number; minimumStock: number }[]>`
          SELECT p.id AS "productId", p.name, p.sku, COALESCE(SUM(w.quantity),0)::int AS quantity, p."minimumStock"
          FROM products p LEFT JOIN warehouse_stock w ON w."productId" = p.id
          WHERE p.status = 'ACTIVE'
          GROUP BY p.id HAVING COALESCE(SUM(w.quantity),0) <= p."minimumStock"
          ORDER BY COALESCE(SUM(w.quantity),0) - p."minimumStock" ASC LIMIT 200`
      : Promise.resolve([]),
    prisma.productRequest.count({ where: { ...storeStockWhere, status: { in: PENDING_REQUESTS } } }),
    prisma.packingOrder.count({
      where: {
        status: { in: context.user.role === Role.STORE ? OPEN_PACKING.filter((s) => s !== PackingOrderStatus.DRAFT) : OPEN_PACKING },
        ...(storeIds === null ? {} : { stores: { some: { storeId: { in: storeIds }, status: { in: ['PENDING', 'DISPATCHED'] } } } }),
      },
    }),
    prisma.stockTransfer.count({
      where: {
        status: { in: OPEN_TRANSFERS },
        ...(storeIds === null ? {} : { OR: [{ toStoreId: { in: storeIds } }, { fromStoreId: { in: storeIds } }] }),
      },
    }),
    prisma.store.count({ where: { status: RecordStatus.ACTIVE, ...(storeIds === null ? {} : { id: { in: storeIds } }) } }),
    prisma.product.count({ where: { status: RecordStatus.ACTIVE } }),
  ]);

  const warehouseQty = warehouseUnits?._sum.quantity ?? 0;
  const lowStockProducts = isAdmin
    ? lowWarehouse.map((r) => ({ ...r, location: 'Central warehouse' }))
    : lowStoreRows.map((r) => ({ ...r, location: r.storeName }));

  return {
    role: context.user.role,
    scope: storeIds === null ? 'ALL' : storeIds.length === 1 ? 'STORE' : 'STORES',
    cards: {
      totalStores: stores,
      totalProducts: products,
      totalStock: (storeUnits._sum.quantity ?? 0) + warehouseQty,
      storeStock: storeUnits._sum.quantity ?? 0,
      warehouseStock: isAdmin ? warehouseQty : undefined,
      warehouseReserved: isAdmin ? warehouseUnits?._sum.reservedQuantity ?? 0 : undefined,
      damagedStock: storeUnits._sum.damagedQuantity ?? 0,
      lowStock: isAdmin ? lowWarehouse.length + lowStoreRows.length : lowStoreRows.length,
      pendingRequests,
      pendingPackingOrders: packing,
      pendingTransfers: transfers,
      todaySales: salesToday[0]?.total ?? 0,
      todayInvoices: Number(salesToday[0]?.count ?? 0),
      monthlySales: salesMonth[0]?.total ?? 0,
      monthlyInvoices: Number(salesMonth[0]?.count ?? 0),
    },
    charts: {
      salesTrend: trend.map((t) => ({ date: t.day, total: t.total, invoices: Number(t.count) })),
      storeSales: storeSales.map((s) => ({ storeId: s.storeId, name: s.name, total: s.total, invoices: Number(s.count) })),
      topProducts: topProducts.map((p) => ({ ...p, quantity: Number(p.quantity) })),
      stockMovement: movementTrend.map((m) => ({ date: m.day, inbound: Number(m.inbound), outbound: Number(m.outbound) })),
      lowStockProducts: lowStockProducts.slice(0, 10),
    },
    currency: { code: settings.currencyCode, symbol: settings.currencySymbol },
  };
}
