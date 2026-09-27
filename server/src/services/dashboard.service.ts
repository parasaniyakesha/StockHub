import { PackingOrderStatus, ProductRequestStatus, RecordStatus, Role, TransferStatus } from '@prisma/client';
import { prisma } from '../utils/prisma';
import { RequestContext } from '../types/auth';
import { getSettings } from './settings.service';
import { reportStoreIds, storeWhere } from './reportScope';

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
  const storeIds = await reportStoreIds(context, q);
  const isAdmin = context.user.role === Role.ADMIN && !q.storeId;
  const storeFilter = storeWhere(storeIds);

  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const thirtyDaysAgo = new Date(todayStart.getTime() - 29 * 86_400_000);
  const fourteenDaysAgo = new Date(todayStart.getTime() - 13 * 86_400_000);

  const [
    salesTodayAgg,
    salesMonthAgg,
    recentSales,
    monthSales,
    recentSaleItems,
    recentMovements,
    storeUnits,
    warehouseUnits,
    storeStockItems,
    whStock,
    pendingRequests,
    packing,
    transfers,
    stores,
    products,
  ] = await Promise.all([
    prisma.sale.aggregate({
      where: { status: 'COMPLETED', ...storeFilter, createdAt: { gte: todayStart } },
      _sum: { grandTotal: true },
      _count: true,
    }),
    prisma.sale.aggregate({
      where: { status: 'COMPLETED', ...storeFilter, createdAt: { gte: monthStart } },
      _sum: { grandTotal: true },
      _count: true,
    }),
    prisma.sale.findMany({
      where: { status: 'COMPLETED', ...storeFilter, createdAt: { gte: thirtyDaysAgo } },
      select: { createdAt: true, grandTotal: true },
    }),
    prisma.sale.findMany({
      where: { status: 'COMPLETED', ...storeFilter, createdAt: { gte: monthStart } },
      include: { store: { select: { id: true, name: true } } },
    }),
    prisma.saleItem.findMany({
      where: {
        sale: { status: 'COMPLETED', ...storeFilter, createdAt: { gte: thirtyDaysAgo } },
      },
      include: { product: { select: { id: true, name: true, sku: true } } },
    }),
    prisma.stockMovement.findMany({
      where: {
        bucket: 'AVAILABLE',
        createdAt: { gte: fourteenDaysAgo },
        ...(isAdmin ? {} : storeFilter),
      },
      select: { createdAt: true, quantity: true },
    }),
    prisma.storeStock.aggregate({ where: storeFilter, _sum: { quantity: true, damagedQuantity: true } }),
    isAdmin ? prisma.warehouseStock.aggregate({ _sum: { quantity: true, reservedQuantity: true } }) : Promise.resolve(null),
    prisma.storeStock.findMany({
      where: {
        ...storeFilter,
        store: { status: 'ACTIVE' },
        product: { status: 'ACTIVE' },
      },
      include: {
        product: { select: { id: true, name: true, sku: true, minimumStock: true } },
        store: { select: { id: true, name: true } },
      },
    }),
    isAdmin
      ? prisma.warehouseStock.findMany({
          where: { product: { status: 'ACTIVE' } },
          include: { product: { select: { id: true, name: true, sku: true, minimumStock: true } } },
        })
      : Promise.resolve([]),
    prisma.productRequest.count({ where: { ...storeFilter, status: { in: PENDING_REQUESTS } } }),
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

  // Daily sales trend (30 days)
  const trendMap = new Map<string, { day: Date; total: number; count: number }>();
  for (let i = 0; i < 30; i++) {
    const d = new Date(thirtyDaysAgo.getTime() + i * 86_400_000);
    const key = d.toISOString().slice(0, 10);
    trendMap.set(key, { day: d, total: 0, count: 0 });
  }
  for (const s of recentSales) {
    const key = s.createdAt.toISOString().slice(0, 10);
    const entry = trendMap.get(key);
    if (entry) {
      entry.total += Number(s.grandTotal);
      entry.count += 1;
    }
  }
  const trend = Array.from(trendMap.values());

  // Store sales breakdown this month
  const storeSalesMap = new Map<string, { storeId: string; name: string; total: number; count: number }>();
  for (const s of monthSales) {
    const sid = s.storeId;
    const entry = storeSalesMap.get(sid) ?? { storeId: sid, name: s.store.name, total: 0, count: 0 };
    entry.total += Number(s.grandTotal);
    entry.count += 1;
    storeSalesMap.set(sid, entry);
  }
  const storeSales = Array.from(storeSalesMap.values()).sort((a, b) => b.total - a.total).slice(0, 10);

  // Top products (last 30 days)
  const topProdMap = new Map<string, { productId: string; name: string; sku: string; quantity: number; total: number }>();
  for (const item of recentSaleItems) {
    const pid = item.productId;
    const entry = topProdMap.get(pid) ?? { productId: pid, name: item.product.name, sku: item.product.sku, quantity: 0, total: 0 };
    entry.quantity += item.quantity;
    entry.total += Number(item.total);
    topProdMap.set(pid, entry);
  }
  const topProducts = Array.from(topProdMap.values()).sort((a, b) => b.quantity - a.quantity).slice(0, 10);

  // Stock movements trend (last 14 days)
  const moveMap = new Map<string, { day: Date; inbound: number; outbound: number }>();
  for (let i = 0; i < 14; i++) {
    const d = new Date(fourteenDaysAgo.getTime() + i * 86_400_000);
    const key = d.toISOString().slice(0, 10);
    moveMap.set(key, { day: d, inbound: 0, outbound: 0 });
  }
  for (const m of recentMovements) {
    const key = m.createdAt.toISOString().slice(0, 10);
    const entry = moveMap.get(key);
    if (entry) {
      if (m.quantity > 0) entry.inbound += m.quantity;
      else if (m.quantity < 0) entry.outbound += -m.quantity;
    }
  }
  const movementTrend = Array.from(moveMap.values());

  // Low stock calculation
  const lowStoreRows = storeStockItems
    .filter((ss) => ss.quantity <= ss.product.minimumStock)
    .map((ss) => ({
      storeId: ss.storeId,
      storeName: ss.store.name,
      productId: ss.productId,
      name: ss.product.name,
      sku: ss.product.sku,
      quantity: ss.quantity,
      minimumStock: ss.product.minimumStock,
    }))
    .sort((a, b) => a.quantity - a.minimumStock - (b.quantity - b.minimumStock))
    .slice(0, 200);

  let lowWarehouse: { productId: string; name: string; sku: string; quantity: number; minimumStock: number }[] = [];
  if (isAdmin) {
    const whProdMap = new Map<string, { productId: string; name: string; sku: string; quantity: number; minimumStock: number }>();
    for (const w of whStock) {
      const pid = w.productId;
      const entry = whProdMap.get(pid) ?? { productId: pid, name: w.product.name, sku: w.product.sku, quantity: 0, minimumStock: w.product.minimumStock };
      entry.quantity += w.quantity;
      whProdMap.set(pid, entry);
    }
    lowWarehouse = Array.from(whProdMap.values())
      .filter((w) => w.quantity <= w.minimumStock)
      .sort((a, b) => a.quantity - a.minimumStock - (b.quantity - b.minimumStock))
      .slice(0, 200);
  }

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
      todaySales: salesTodayAgg._sum.grandTotal ?? 0,
      todayInvoices: salesTodayAgg._count,
      monthlySales: salesMonthAgg._sum.grandTotal ?? 0,
      monthlyInvoices: salesMonthAgg._count,
    },
    charts: {
      salesTrend: trend.map((t) => ({ date: t.day, total: t.total, invoices: t.count })),
      storeSales: storeSales.map((s) => ({ storeId: s.storeId, name: s.name, total: s.total, invoices: s.count })),
      topProducts: topProducts.map((p) => ({ ...p, quantity: p.quantity })),
      stockMovement: movementTrend.map((m) => ({ date: m.day, inbound: m.inbound, outbound: m.outbound })),
      lowStockProducts: lowStockProducts.slice(0, 10),
    },
    currency: { code: settings.currencyCode, symbol: settings.currencySymbol },
  };
}
