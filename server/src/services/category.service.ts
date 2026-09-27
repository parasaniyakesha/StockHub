import { Prisma, RecordStatus, Role } from '@prisma/client';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { contains, orderBy, pageArgs } from '../utils/pagination';
import { RequestContext } from '../types/auth';
import { audit, diff } from './audit.service';
import { categoryListQuery, createCategorySchema, updateCategorySchema } from '../validators/catalog.validator';

type CategoryListQuery = z.infer<typeof categoryListQuery>;

const include = {
  parent: { select: { id: true, name: true, code: true } },
  _count: { select: { products: true, children: true } },
} satisfies Prisma.CategoryInclude;

export async function listCategories(context: RequestContext, q: CategoryListQuery) {
  const search = contains(q.search);
  const where: Prisma.CategoryWhereInput = {
    // Non-admins only see the active catalog.
    ...(context.user.role !== Role.ADMIN ? { status: RecordStatus.ACTIVE } : q.status ? { status: q.status as RecordStatus } : {}),
    ...(q.parentId === 'root' ? { parentId: null } : q.parentId ? { parentId: q.parentId } : {}),
    ...(search ? { OR: [{ name: search }, { code: search }] } : {}),
  };
  const sort = orderBy(q, {
    name: (d) => ({ name: d }),
    code: (d) => ({ code: d }),
    status: (d) => ({ status: d }),
    createdAt: (d) => ({ createdAt: d }),
  }, { name: 'asc' });

  if (q.all) {
    const rows = await prisma.category.findMany({ where, include, orderBy: sort });
    return { rows, total: rows.length };
  }
  const [rows, total] = await Promise.all([
    prisma.category.findMany({ where, include, orderBy: sort, ...pageArgs(q) }),
    prisma.category.count({ where }),
  ]);
  return { rows, total };
}

export async function getCategory(id: string) {
  const category = await prisma.category.findUnique({
    where: { id },
    include: { ...include, children: { select: { id: true, name: true, code: true, status: true } } },
  });
  if (!category) throw ApiError.notFound('Category');
  return category;
}

export async function categoryWithDescendants(id: string): Promise<string[]> {
  const results = [id];
  let currentLevel = [id];
  while (currentLevel.length > 0) {
    const children = await prisma.category.findMany({
      where: { parentId: { in: currentLevel } },
      select: { id: true },
    });
    if (children.length === 0) break;
    const nextLevel = children.map((c) => c.id);
    results.push(...nextLevel);
    currentLevel = nextLevel;
  }
  return results;
}

async function assertValidParent(id: string | null, parentId: string | null | undefined) {
  if (!parentId) return;
  const parent = await prisma.category.findUnique({ where: { id: parentId }, select: { id: true } });
  if (!parent) throw ApiError.validation([{ field: 'parentId', message: 'Parent category does not exist' }]);
  if (id && (await categoryWithDescendants(id)).includes(parentId)) {
    throw ApiError.validation([{ field: 'parentId', message: 'A category cannot be placed under itself or its subcategory' }]);
  }
}

export async function createCategory(context: RequestContext, input: z.infer<typeof createCategorySchema>) {
  await assertValidParent(null, input.parentId);
  return prisma.$transaction(async (tx) => {
    const category = await tx.category.create({ data: input, include });
    await audit(tx, context, { action: 'CREATE', module: 'categories', recordId: category.id, summary: `Created category ${category.name}`, newValue: input });
    return category;
  });
}

export async function updateCategory(context: RequestContext, id: string, input: z.infer<typeof updateCategorySchema>) {
  const existing = await prisma.category.findUnique({ where: { id } });
  if (!existing) throw ApiError.notFound('Category');
  await assertValidParent(id, input.parentId);
  return prisma.$transaction(async (tx) => {
    const category = await tx.category.update({ where: { id }, data: input, include });
    const { oldValue, newValue, changed } = diff(existing, input);
    if (changed) await audit(tx, context, { action: 'UPDATE', module: 'categories', recordId: id, summary: `Updated category ${category.name}`, oldValue, newValue });
    return category;
  });
}

export async function setCategoryStatus(context: RequestContext, id: string, status: RecordStatus) {
  const existing = await prisma.category.findUnique({ where: { id } });
  if (!existing) throw ApiError.notFound('Category');
  return prisma.$transaction(async (tx) => {
    const category = await tx.category.update({ where: { id }, data: { status }, include });
    await audit(tx, context, {
      action: status === RecordStatus.ACTIVE ? 'ACTIVATE' : 'DEACTIVATE',
      module: 'categories',
      recordId: id,
      summary: `${status === RecordStatus.ACTIVE ? 'Activated' : 'Deactivated'} category ${category.name}`,
      oldValue: { status: existing.status },
      newValue: { status },
    });
    return category;
  });
}

export async function assignProducts(context: RequestContext, id: string, productIds: string[]) {
  const category = await prisma.category.findUnique({ where: { id }, select: { id: true, name: true } });
  if (!category) throw ApiError.notFound('Category');
  return prisma.$transaction(async (tx) => {
    const before = await tx.product.findMany({ where: { id: { in: productIds } }, select: { id: true, categoryId: true } });
    if (before.length !== productIds.length) throw ApiError.validation([{ field: 'productIds', message: 'One or more products do not exist' }]);
    const result = await tx.product.updateMany({ where: { id: { in: productIds } }, data: { categoryId: id } });
    await audit(tx, context, {
      action: 'ASSIGN_PRODUCTS',
      module: 'categories',
      recordId: id,
      summary: `Moved ${result.count} product(s) to category ${category.name}`,
      oldValue: before,
      newValue: { categoryId: id, productIds },
    });
    return { updated: result.count };
  });
}
