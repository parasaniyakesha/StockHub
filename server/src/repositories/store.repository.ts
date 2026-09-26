import { Prisma } from '@prisma/client';
import { prisma } from '../utils/prisma';
import { contains, orderBy, pageArgs } from '../utils/pagination';
import { ListQuery } from '../validators/common.validator';

export const storeInclude = {
  assignedManager: { select: { id: true, name: true, email: true } },
  _count: { select: { users: true } },
} satisfies Prisma.StoreInclude;

export const storeRepository = {
  buildWhere(q: ListQuery & { city?: string }, idFilter?: { in: string[] } | string): Prisma.StoreWhereInput {
    const search = contains(q.search);
    return {
      ...(idFilter ? { id: idFilter } : {}),
      ...(q.status ? { status: q.status as 'ACTIVE' | 'INACTIVE' } : {}),
      ...(q.managerId ? { assignedManagerId: q.managerId } : {}),
      ...(q.city ? { city: { equals: q.city, mode: 'insensitive' } } : {}),
      ...(search ? { OR: [{ name: search }, { code: search }, { city: search }, { contactPerson: search }] } : {}),
    };
  },

  async list(where: Prisma.StoreWhereInput, q: ListQuery) {
    const [rows, total] = await Promise.all([
      prisma.store.findMany({
        where,
        include: storeInclude,
        orderBy: orderBy(q, {
          name: (d) => ({ name: d }),
          code: (d) => ({ code: d }),
          city: (d) => ({ city: d }),
          status: (d) => ({ status: d }),
          createdAt: (d) => ({ createdAt: d }),
        }, { name: 'asc' }),
        ...pageArgs(q),
      }),
      prisma.store.count({ where }),
    ]);
    return { rows, total };
  },

  findById: (id: string) =>
    prisma.store.findUnique({
      where: { id },
      include: {
        ...storeInclude,
        users: { select: { id: true, name: true, email: true, status: true, lastLoginAt: true }, orderBy: { name: 'asc' } },
      },
    }),
};
