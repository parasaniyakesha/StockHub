import { RecordStatus, Role } from '@prisma/client';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { storeRepository } from '../repositories/store.repository';
import { assertRecordInScope, storeFilter } from '../middleware/storeScope';
import { RequestContext } from '../types/auth';
import { audit, diff } from './audit.service';
import { createStoreSchema, storeListQuery, updateStoreSchema } from '../validators/catalog.validator';

type StoreListQuery = z.infer<typeof storeListQuery>;

export async function listStores(context: RequestContext, q: StoreListQuery) {
  const where = storeRepository.buildWhere(q, storeFilter(context.scope, q.storeId));
  return storeRepository.list(where, q);
}

export async function getStore(context: RequestContext, id: string) {
  assertRecordInScope(context.scope, [id], 'Store');
  const store = await storeRepository.findById(id);
  if (!store) throw ApiError.notFound('Store');
  return store;
}

async function assertManager(managerId: string | null | undefined) {
  if (!managerId) return;
  const manager = await prisma.user.findUnique({ where: { id: managerId }, select: { role: true, status: true } });
  if (!manager || manager.role !== Role.MANAGER) {
    throw ApiError.validation([{ field: 'assignedManagerId', message: 'Selected user is not a manager' }]);
  }
  if (manager.status !== RecordStatus.ACTIVE) {
    throw ApiError.validation([{ field: 'assignedManagerId', message: 'Selected manager is inactive' }]);
  }
}

export async function createStore(context: RequestContext, input: z.infer<typeof createStoreSchema>) {
  await assertManager(input.assignedManagerId);
  return prisma.$transaction(async (tx) => {
    const store = await tx.store.create({ data: input });
    await audit(tx, context, { action: 'CREATE', module: 'stores', recordId: store.id, summary: `Created store ${store.name} (${store.code})`, newValue: store });
    return store;
  });
}

export async function updateStore(context: RequestContext, id: string, input: z.infer<typeof updateStoreSchema>) {
  const existing = await prisma.store.findUnique({ where: { id } });
  if (!existing) throw ApiError.notFound('Store');
  await assertManager(input.assignedManagerId);
  return prisma.$transaction(async (tx) => {
    const store = await tx.store.update({ where: { id }, data: input });
    const { oldValue, newValue, changed } = diff(existing, input);
    if (changed) {
      await audit(tx, context, { action: 'UPDATE', module: 'stores', recordId: id, summary: `Updated store ${store.name}`, oldValue, newValue });
    }
    return store;
  });
}

export async function setStoreStatus(context: RequestContext, id: string, status: RecordStatus) {
  const existing = await prisma.store.findUnique({ where: { id } });
  if (!existing) throw ApiError.notFound('Store');
  return prisma.$transaction(async (tx) => {
    const store = await tx.store.update({ where: { id }, data: { status } });
    await audit(tx, context, {
      action: status === RecordStatus.ACTIVE ? 'ACTIVATE' : 'DEACTIVATE',
      module: 'stores',
      recordId: id,
      summary: `${status === RecordStatus.ACTIVE ? 'Activated' : 'Deactivated'} store ${store.name}`,
      oldValue: { status: existing.status },
      newValue: { status },
    });
    return store;
  });
}

export async function assignManager(context: RequestContext, id: string, managerId: string | null) {
  return updateStore(context, id, { assignedManagerId: managerId });
}

/**
 * A store with any history (users, stock, sales, requests, transfers, ...)
 * can never be hard-deleted - the ledger and audit trail must stay intact -
 * so it is deactivated instead. Only a completely clean store is removed.
 */
export async function deleteStore(context: RequestContext, id: string) {
  const existing = await prisma.store.findUnique({ where: { id } });
  if (!existing) throw ApiError.notFound('Store');

  const [users, stock, availability, movements, sales, returns, requests, packingStores, transfersOut, transfersIn] = await Promise.all([
    prisma.user.count({ where: { storeId: id } }),
    prisma.storeStock.count({ where: { storeId: id } }),
    prisma.storeAvailability.count({ where: { storeId: id } }),
    prisma.stockMovement.count({ where: { storeId: id } }),
    prisma.sale.count({ where: { storeId: id } }),
    prisma.saleReturn.count({ where: { storeId: id } }),
    prisma.productRequest.count({ where: { storeId: id } }),
    prisma.packingOrderStore.count({ where: { storeId: id } }),
    prisma.stockTransfer.count({ where: { fromStoreId: id } }),
    prisma.stockTransfer.count({ where: { toStoreId: id } }),
  ]);
  const hasHistory = users + stock + availability + movements + sales + returns + requests + packingStores + transfersOut + transfersIn > 0;
  if (hasHistory) {
    await setStoreStatus(context, id, RecordStatus.INACTIVE);
    return { deleted: false, deactivated: true };
  }

  await prisma.$transaction(async (tx) => {
    await tx.store.delete({ where: { id } });
    await audit(tx, context, { action: 'DELETE', module: 'stores', recordId: id, summary: `Deleted store ${existing.name} (${existing.code})`, oldValue: existing });
  });
  return { deleted: true, deactivated: false };
}

/** Moves existing STORE-role users into this store. */
export async function assignStoreUsers(context: RequestContext, id: string, userIds: string[]) {
  const store = await prisma.store.findUnique({ where: { id }, select: { id: true, name: true } });
  if (!store) throw ApiError.notFound('Store');
  return prisma.$transaction(async (tx) => {
    const users = await tx.user.findMany({ where: { id: { in: userIds } }, select: { id: true, role: true, storeId: true } });
    if (users.length !== userIds.length) throw ApiError.validation([{ field: 'userIds', message: 'One or more users do not exist' }]);
    if (users.some((u) => u.role !== Role.STORE)) {
      throw ApiError.validation([{ field: 'userIds', message: 'Only store users can be assigned to a store' }]);
    }
    await tx.user.updateMany({ where: { id: { in: userIds } }, data: { storeId: id, tokenVersion: { increment: 1 } } });
    await audit(tx, context, {
      action: 'ASSIGN_USERS',
      module: 'stores',
      recordId: id,
      summary: `Assigned ${userIds.length} user(s) to store ${store.name}`,
      oldValue: users.map((u) => ({ userId: u.id, storeId: u.storeId })),
      newValue: { storeId: id, userIds },
    });
    return storeRepository.findById(id);
  });
}
