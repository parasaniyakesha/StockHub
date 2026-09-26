import { Prisma } from '@prisma/client';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { contains, dateRange, orderBy, pageArgs } from '../utils/pagination';
import { listQuery, optionalString, uuid } from '../validators/common.validator';

export const auditListQuery = listQuery.extend({
  module: optionalString(40),
  action: optionalString(40),
  userId: z.preprocess((v) => (v === '' ? undefined : v), uuid.optional()),
  recordId: optionalString(64),
});

export async function listAuditLogs(q: z.infer<typeof auditListQuery>, take?: number) {
  const search = contains(q.search);
  const where: Prisma.AuditLogWhereInput = {
    ...(q.module ? { module: q.module } : {}),
    ...(q.action ? { action: q.action } : {}),
    ...(q.userId ? { userId: q.userId } : {}),
    ...(q.recordId ? { recordId: q.recordId } : {}),
    ...(dateRange(q) ? { createdAt: dateRange(q) } : {}),
    ...(search ? { OR: [{ summary: search }, { user: { name: search } }, { user: { email: search } }, { recordId: search }] } : {}),
  };
  const [rows, total] = await Promise.all([
    prisma.auditLog.findMany({
      where,
      include: { user: { select: { id: true, name: true, email: true, role: true } } },
      orderBy: orderBy(q, { createdAt: (d) => ({ createdAt: d }), module: (d) => ({ module: d }), action: (d) => ({ action: d }) }, { createdAt: 'desc' }),
      ...(take ? { take } : pageArgs(q)),
    }),
    prisma.auditLog.count({ where }),
  ]);
  return { rows, total };
}

export async function auditFacets() {
  const [modules, actions] = await Promise.all([
    prisma.auditLog.findMany({ distinct: ['module'], select: { module: true }, orderBy: { module: 'asc' } }),
    prisma.auditLog.findMany({ distinct: ['action'], select: { action: true }, orderBy: { action: 'asc' } }),
  ]);
  return { modules: modules.map((m) => m.module), actions: actions.map((a) => a.action) };
}
