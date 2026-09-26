import { Prisma, Role } from '@prisma/client';
import { prisma } from '../utils/prisma';
import { userSelect } from '../models/user.model';
import { contains, orderBy, pageArgs } from '../utils/pagination';
import { ListQuery } from '../validators/common.validator';

export const userRepository = {
  async list(where: Prisma.UserWhereInput, q: ListQuery) {
    const [rows, total] = await Promise.all([
      prisma.user.findMany({
        where,
        select: { ...userSelect, _count: { select: { managedStores: true } } },
        orderBy: orderBy(q, {
          name: (d) => ({ name: d }),
          email: (d) => ({ email: d }),
          role: (d) => ({ role: d }),
          status: (d) => ({ status: d }),
          lastLoginAt: (d) => ({ lastLoginAt: { sort: d, nulls: 'last' } }),
          createdAt: (d) => ({ createdAt: d }),
        }, { name: 'asc' }),
        ...pageArgs(q),
      }),
      prisma.user.count({ where }),
    ]);
    return { rows, total };
  },

  buildWhere(q: ListQuery & { role?: Role }, storeScope?: { in: string[] } | string): Prisma.UserWhereInput {
    const search = contains(q.search);
    return {
      ...(q.role ? { role: q.role } : {}),
      ...(q.status ? { status: q.status as Prisma.EnumRecordStatusFilter['equals'] } : {}),
      ...(storeScope ? { storeId: storeScope } : {}),
      ...(search ? { OR: [{ name: search }, { email: search }, { phone: search }] } : {}),
    };
  },

  findById: (id: string) => prisma.user.findUnique({ where: { id }, select: userSelect }),
};
