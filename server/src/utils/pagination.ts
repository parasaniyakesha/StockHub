import { Prisma } from '@prisma/client';
import { ListQuery } from '../validators/common.validator';

export function pageArgs(q: Pick<ListQuery, 'page' | 'limit'>) {
  return { skip: (q.page - 1) * q.limit, take: q.limit };
}

/** Maps a whitelisted sortBy key to a Prisma orderBy clause. */
export function orderBy<T extends string>(
  q: Pick<ListQuery, 'sortBy' | 'sortOrder'>,
  allowed: Record<T, (dir: Prisma.SortOrder) => object>,
  fallback: object,
) {
  const dir: Prisma.SortOrder = q.sortOrder === 'asc' ? 'asc' : 'desc';
  if (q.sortBy && q.sortBy in allowed) return allowed[q.sortBy as T](dir);
  return fallback;
}

export function dateRange(q: Pick<ListQuery, 'startDate' | 'endDate'>) {
  if (!q.startDate && !q.endDate) return undefined;
  const range: { gte?: Date; lte?: Date } = {};
  if (q.startDate) range.gte = startOfDay(q.startDate);
  if (q.endDate) range.lte = endOfDay(q.endDate);
  return range;
}

export function startOfDay(d: Date) {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}

export function endOfDay(d: Date) {
  const x = new Date(d);
  x.setHours(23, 59, 59, 999);
  return x;
}

export const contains = (search?: string) =>
  search ? { contains: search, mode: Prisma.QueryMode.insensitive } : undefined;
