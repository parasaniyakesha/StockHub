import { Prisma } from '@prisma/client';
import { prisma } from '../utils/prisma';
import { orderBy, pageArgs } from '../utils/pagination';
import { ListQuery } from '../validators/common.validator';
import { StoreScope } from '../types/auth';

export const productInclude = {
  category: { select: { id: true, name: true, code: true } },
} satisfies Prisma.ProductInclude;

export interface StockSummary {
  warehouseQuantity: number;
  warehouseAvailable: number;
  storeQuantity: number;
}

export const productRepository = {
  async list(where: Prisma.ProductWhereInput, q: ListQuery, take?: number) {
    const [rows, total] = await Promise.all([
      prisma.product.findMany({
        where,
        include: productInclude,
        orderBy: orderBy(q, {
          name: (d) => ({ name: d }),
          sku: (d) => ({ sku: d }),
          brand: (d) => ({ brand: d }),
          sellingPrice: (d) => ({ sellingPrice: d }),
          purchasePrice: (d) => ({ purchasePrice: d }),
          status: (d) => ({ status: d }),
          category: (d) => ({ category: { name: d } }),
          createdAt: (d) => ({ createdAt: d }),
          updatedAt: (d) => ({ updatedAt: d }),
        }, { name: 'asc' }),
        ...(take ? { take } : pageArgs(q)),
      }),
      prisma.product.count({ where }),
    ]);
    return { rows, total };
  },

  findById: (id: string) => prisma.product.findUnique({ where: { id }, include: productInclude }),

  /** Aggregated stock per product, restricted to the stores inside the caller's scope. */
  async stockSummary(productIds: string[], scope: StoreScope): Promise<Map<string, StockSummary>> {
    const map = new Map<string, StockSummary>();
    if (!productIds.length) return map;
    productIds.forEach((id) => map.set(id, { warehouseQuantity: 0, warehouseAvailable: 0, storeQuantity: 0 }));

    const [warehouse, stores] = await Promise.all([
      prisma.warehouseStock.groupBy({
        by: ['productId'],
        where: { productId: { in: productIds } },
        _sum: { quantity: true, reservedQuantity: true },
      }),
      scope.all || scope.storeIds.length
        ? prisma.storeStock.groupBy({
            by: ['productId'],
            where: { productId: { in: productIds }, ...(scope.all ? {} : { storeId: { in: scope.storeIds } }) },
            _sum: { quantity: true },
          })
        : Promise.resolve([]),
    ]);

    for (const w of warehouse) {
      const s = map.get(w.productId)!;
      s.warehouseQuantity = w._sum.quantity ?? 0;
      s.warehouseAvailable = (w._sum.quantity ?? 0) - (w._sum.reservedQuantity ?? 0);
    }
    for (const st of stores) map.get(st.productId)!.storeQuantity = st._sum.quantity ?? 0;
    return map;
  },

  /**
   * Products at or below minimum stock. For admins the warehouse is measured;
   * for managers/store users, any of their stores.
   */
  async lowStockIds(scope: StoreScope): Promise<string[]> {
    if (scope.all) {
      const rows = await prisma.$queryRaw<{ id: string }[]>`
        SELECT p.id FROM products p
        LEFT JOIN (SELECT "productId", SUM(quantity) AS qty FROM warehouse_stock GROUP BY "productId") w ON w."productId" = p.id
        WHERE p.status = 'ACTIVE' AND COALESCE(w.qty, 0) <= p."minimumStock"`;
      return rows.map((r) => r.id);
    }
    if (!scope.storeIds.length) return [];
    const rows = await prisma.$queryRaw<{ id: string }[]>`
      SELECT DISTINCT p.id FROM products p
      JOIN store_stock s ON s."productId" = p.id
      WHERE p.status = 'ACTIVE' AND s."storeId" IN (${Prisma.join(scope.storeIds)}) AND s.quantity <= p."minimumStock"`;
    return rows.map((r) => r.id);
  },
};
