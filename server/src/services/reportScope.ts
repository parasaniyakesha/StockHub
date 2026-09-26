import { Prisma, Role } from '@prisma/client';
import { prisma } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { assertStoreAccess } from '../middleware/storeScope';
import { RequestContext } from '../types/auth';

/**
 * Resolves which stores a report/dashboard may aggregate.
 * Returns null for "all stores" (admin without filters).
 */
export async function reportStoreIds(
  context: RequestContext,
  q: { storeId?: string; managerId?: string },
): Promise<string[] | null> {
  if (q.storeId) {
    assertStoreAccess(context.scope, q.storeId);
    return [q.storeId];
  }
  if (q.managerId) {
    if (context.user.role === Role.STORE) throw ApiError.forbidden();
    if (context.user.role === Role.MANAGER && q.managerId !== context.user.id) throw ApiError.forbidden();
    const stores = await prisma.store.findMany({ where: { assignedManagerId: q.managerId }, select: { id: true } });
    return stores.map((s) => s.id);
  }
  return context.scope.all ? null : context.scope.storeIds;
}

/** SQL predicate `<column> IN (...)` honouring the resolved scope. */
export function storeSql(column: string, storeIds: string[] | null) {
  if (storeIds === null) return Prisma.sql`TRUE`;
  if (!storeIds.length) return Prisma.sql`FALSE`;
  return Prisma.sql`${Prisma.raw(column)} IN (${Prisma.join(storeIds)})`;
}

export const storeWhere = (storeIds: string[] | null) => (storeIds === null ? {} : { storeId: { in: storeIds } });

/** Local-time expression for a UTC timestamp column. */
export const localTs = (column: string, tz: string) => Prisma.sql`((${Prisma.raw(column)} AT TIME ZONE 'UTC') AT TIME ZONE ${tz})`;
