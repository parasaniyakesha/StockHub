import { Prisma, RecordStatus, Role } from '@prisma/client';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { contains } from '../utils/pagination';
import { productInclude, productRepository } from '../repositories/product.repository';
import { RequestContext } from '../types/auth';
import { audit, diff } from './audit.service';
import { categoryWithDescendants } from './category.service';
import { createProductSchema, productListQuery, updateProductSchema } from '../validators/catalog.validator';
import { EXPORT_LIMIT } from './export.service';

type ProductListQuery = z.infer<typeof productListQuery>;
type CreateProduct = z.infer<typeof createProductSchema>;
type UpdateProduct = z.infer<typeof updateProductSchema>;
type ProductRow = Prisma.ProductGetPayload<{ include: typeof productInclude }>;

/** Store users must not see cost prices. */
function project(context: RequestContext, p: ProductRow) {
  if (context.user.role === Role.STORE) {
    const { purchasePrice: _hidden, ...rest } = p;
    return rest;
  }
  return p;
}

async function buildWhere(context: RequestContext, q: ProductListQuery): Promise<Prisma.ProductWhereInput> {
  const search = contains(q.search);
  const where: Prisma.ProductWhereInput = {
    // Non-admins browse the active catalog only.
    ...(context.user.role !== Role.ADMIN ? { status: RecordStatus.ACTIVE } : q.status ? { status: q.status as RecordStatus } : {}),
    ...(q.brand ? { brand: { equals: q.brand, mode: 'insensitive' } } : {}),
    ...(search ? { OR: [{ name: search }, { sku: search }, { barcode: search }, { brand: search }] } : {}),
  };
  if (q.categoryId) where.categoryId = { in: await categoryWithDescendants(q.categoryId) };
  if (q.lowStock) where.id = { in: await productRepository.lowStockIds(context.scope) };
  return where;
}

export async function listProducts(context: RequestContext, q: ProductListQuery) {
  const { rows, total } = await productRepository.list(await buildWhere(context, q), q);
  const stock = await productRepository.stockSummary(rows.map((r) => r.id), context.scope);
  return {
    rows: rows.map((p) => {
      const s = stock.get(p.id)!;
      return {
        ...project(context, p),
        // Store users never see central warehouse figures.
        ...(context.user.role === Role.STORE ? { storeQuantity: s.storeQuantity } : s),
      };
    }),
    total,
  };
}

export async function exportProducts(context: RequestContext, q: ProductListQuery) {
  const { rows } = await productRepository.list(await buildWhere(context, q), { ...q, page: 1 }, EXPORT_LIMIT);
  const stock = await productRepository.stockSummary(rows.map((r) => r.id), context.scope);
  return rows.map((p) => ({ ...p, ...stock.get(p.id)! }));
}

export async function getProduct(context: RequestContext, id: string) {
  const product = await productRepository.findById(id);
  if (!product || (context.user.role !== Role.ADMIN && product.status !== RecordStatus.ACTIVE)) {
    throw ApiError.notFound('Product');
  }
  const [warehouseStock, storeStock] = await Promise.all([
    context.user.role === Role.STORE
      ? Promise.resolve([])
      : prisma.warehouseStock.findMany({
          where: { productId: id },
          include: { warehouse: { select: { id: true, name: true, code: true } } },
        }),
    prisma.storeStock.findMany({
      where: { productId: id, ...(context.scope.all ? {} : { storeId: { in: context.scope.storeIds } }) },
      include: { store: { select: { id: true, name: true, code: true } } },
      orderBy: { store: { name: 'asc' } },
    }),
  ]);
  return { ...project(context, product), warehouseStock, storeStock };
}

async function assertActiveCategory(categoryId: string) {
  const category = await prisma.category.findUnique({ where: { id: categoryId }, select: { status: true } });
  if (!category) throw ApiError.validation([{ field: 'categoryId', message: 'Category does not exist' }]);
  if (category.status !== RecordStatus.ACTIVE) {
    throw ApiError.validation([{ field: 'categoryId', message: 'Category is inactive' }]);
  }
}

export async function createProduct(context: RequestContext, input: CreateProduct) {
  await assertActiveCategory(input.categoryId);
  return prisma.$transaction(async (tx) => {
    const product = await tx.product.create({ data: input, include: productInclude });
    await audit(tx, context, {
      action: 'CREATE',
      module: 'products',
      recordId: product.id,
      summary: `Created product ${product.name} (${product.sku})`,
      newValue: input,
    });
    return product;
  });
}

export async function updateProduct(context: RequestContext, id: string, input: UpdateProduct) {
  const existing = await prisma.product.findUnique({ where: { id } });
  if (!existing) throw ApiError.notFound('Product');
  if (input.categoryId && input.categoryId !== existing.categoryId) await assertActiveCategory(input.categoryId);

  const min = input.minimumStock ?? existing.minimumStock;
  const max = input.maximumStock === undefined ? existing.maximumStock : input.maximumStock;
  if (max != null && max < min) {
    throw ApiError.validation([{ field: 'maximumStock', message: 'Maximum stock must be greater than minimum stock' }]);
  }

  return prisma.$transaction(async (tx) => {
    const product = await tx.product.update({ where: { id }, data: input, include: productInclude });
    const { oldValue, newValue, changed } = diff(existing as unknown as Record<string, unknown>, input);
    if (changed) {
      const priceChanged = 'sellingPrice' in newValue || 'purchasePrice' in newValue;
      await audit(tx, context, {
        action: priceChanged ? 'PRICE_CHANGE' : 'UPDATE',
        module: 'products',
        recordId: id,
        summary: priceChanged
          ? `Changed ${product.name} price${'sellingPrice' in newValue ? ` (selling ${existing.sellingPrice} → ${product.sellingPrice})` : ''}`
          : `Updated product ${product.name}`,
        oldValue,
        newValue,
      });
    }
    return product;
  });
}

export async function setProductStatus(context: RequestContext, id: string, status: RecordStatus) {
  const existing = await prisma.product.findUnique({ where: { id } });
  if (!existing) throw ApiError.notFound('Product');
  return prisma.$transaction(async (tx) => {
    const product = await tx.product.update({ where: { id }, data: { status }, include: productInclude });
    await audit(tx, context, {
      action: status === RecordStatus.ACTIVE ? 'ACTIVATE' : 'DEACTIVATE',
      module: 'products',
      recordId: id,
      summary: `${status === RecordStatus.ACTIVE ? 'Activated' : 'Deactivated'} product ${product.name}`,
      oldValue: { status: existing.status },
      newValue: { status },
    });
    return product;
  });
}

/**
 * Products with stock history can never be hard-deleted (the ledger must stay
 * intact) - they are deactivated instead.
 */
export async function deleteProduct(context: RequestContext, id: string) {
  const existing = await prisma.product.findUnique({ where: { id } });
  if (!existing) throw ApiError.notFound('Product');
  const [movements, saleItems, requestItems, packingItems, transferItems] = await Promise.all([
    prisma.stockMovement.count({ where: { productId: id } }),
    prisma.saleItem.count({ where: { productId: id } }),
    prisma.productRequestItem.count({ where: { productId: id } }),
    prisma.packingOrderItem.count({ where: { productId: id } }),
    prisma.stockTransferItem.count({ where: { productId: id } }),
  ]);
  if (movements + saleItems + requestItems + packingItems + transferItems > 0) {
    await setProductStatus(context, id, RecordStatus.INACTIVE);
    return { deleted: false, deactivated: true };
  }
  await prisma.$transaction(async (tx) => {
    await tx.warehouseStock.deleteMany({ where: { productId: id } });
    await tx.storeStock.deleteMany({ where: { productId: id } });
    await tx.storeAvailability.deleteMany({ where: { productId: id } });
    await tx.product.delete({ where: { id } });
    await audit(tx, context, { action: 'DELETE', module: 'products', recordId: id, summary: `Deleted product ${existing.name} (${existing.sku})`, oldValue: existing });
  });
  return { deleted: true, deactivated: false };
}

/**
 * Bulk import: rows are validated individually; valid rows are upserted by SKU
 * inside one transaction, invalid rows are reported back with their row number.
 */
export async function importProducts(context: RequestContext, rows: Record<string, unknown>[]) {
  const categories = await prisma.category.findMany({ select: { id: true, code: true, status: true } });
  const byCode = new Map(categories.map((c) => [c.code.toUpperCase(), c]));
  const errors: { row: number; message: string }[] = [];
  const valid: CreateProduct[] = [];

  for (const [index, raw] of rows.entries()) {
    const rowNo = index + 2; // +1 header, +1 one-based
    const categoryCode = String(raw.categoryCode ?? '').trim().toUpperCase();
    const category = byCode.get(categoryCode);
    if (!category) {
      errors.push({ row: rowNo, message: `Unknown category code "${categoryCode}"` });
      continue;
    }
    if (category.status !== RecordStatus.ACTIVE) {
      errors.push({ row: rowNo, message: `Category ${categoryCode} is inactive` });
      continue;
    }
    const parsed = createProductSchema.safeParse({ ...raw, categoryId: category.id });
    if (!parsed.success) {
      errors.push({ row: rowNo, message: parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ') });
      continue;
    }
    valid.push(parsed.data);
  }

  const seen = new Set<string>();
  valid.forEach((p, i) => {
    if (seen.has(p.sku)) errors.push({ row: i + 2, message: `Duplicate SKU ${p.sku} in file` });
    seen.add(p.sku);
  });
  if (errors.length) return { created: 0, updated: 0, errors };

  let created = 0;
  let updated = 0;
  await prisma.$transaction(async (tx) => {
    const existing = new Set((await tx.product.findMany({ where: { sku: { in: valid.map((v) => v.sku) } }, select: { sku: true } })).map((p) => p.sku));
    for (const p of valid) {
      await tx.product.upsert({ where: { sku: p.sku }, create: p, update: p });
      existing.has(p.sku) ? updated++ : created++;
    }
    await audit(tx, context, {
      action: 'IMPORT',
      module: 'products',
      summary: `Imported products: ${created} created, ${updated} updated`,
      newValue: { skus: valid.map((v) => v.sku) },
    });
  }, { timeout: 60_000 });

  return { created, updated, errors };
}
