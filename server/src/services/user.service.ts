import { Prisma, RecordStatus, Role } from '@prisma/client';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { hashPassword } from '../utils/crypto';
import { toUserDto, userSelect } from '../models/user.model';
import { userRepository } from '../repositories/user.repository';
import { assertStoreAccess, storeFilter } from '../middleware/storeScope';
import { RequestContext } from '../types/auth';
import { DEFAULT_MANAGER_PERMISSIONS } from '../config/permissions';
import { audit, diff } from './audit.service';
import { createUserSchema, updateUserSchema, userListQuery } from '../validators/user.validator';

type CreateUser = z.infer<typeof createUserSchema>;
type UpdateUser = z.infer<typeof updateUserSchema>;
type UserListQuery = z.infer<typeof userListQuery>;

const isAdmin = (c: RequestContext) => c.user.role === Role.ADMIN;

/**
 * Admins manage every user. Managers holding users.manage may only manage STORE
 * users of their own assigned stores.
 */
function assertCanManage(context: RequestContext, target: { role: Role; storeId: string | null }) {
  if (isAdmin(context)) return;
  if (target.role !== Role.STORE) throw ApiError.forbidden('Managers can only manage store users');
  assertStoreAccess(context.scope, target.storeId);
}

export async function listUsers(context: RequestContext, q: UserListQuery) {
  let where: Prisma.UserWhereInput;
  if (isAdmin(context)) {
    where = userRepository.buildWhere(q, q.storeId);
  } else {
    if (q.role && q.role !== Role.STORE) return { rows: [], total: 0 };
    where = userRepository.buildWhere({ ...q, role: Role.STORE }, storeFilter(context.scope, q.storeId));
  }
  const { rows, total } = await userRepository.list(where, q);
  return {
    rows: rows.map((u) => ({ ...toUserDto(u), managedStoreCount: u._count.managedStores })),
    total,
  };
}

export async function getUser(context: RequestContext, id: string) {
  const user = await userRepository.findById(id);
  if (!user) throw ApiError.notFound('User');
  if (!isAdmin(context)) {
    if (user.role !== Role.STORE || !user.storeId || !context.scope.storeIds.includes(user.storeId)) {
      throw ApiError.notFound('User');
    }
  }
  return toUserDto(user);
}

async function assertStoreExists(tx: Prisma.TransactionClient, storeId: string) {
  const store = await tx.store.findUnique({ where: { id: storeId }, select: { id: true } });
  if (!store) throw ApiError.validation([{ field: 'storeId', message: 'Store does not exist' }]);
}

export async function createUser(context: RequestContext, input: CreateUser) {
  assertCanManage(context, { role: input.role, storeId: input.storeId ?? null });

  const passwordHash = await hashPassword(input.password);
  return prisma.$transaction(async (tx) => {
    if (input.role === Role.STORE) await assertStoreExists(tx, input.storeId!);

    const user = await tx.user.create({
      data: {
        name: input.name,
        email: input.email,
        phone: input.phone ?? null,
        passwordHash,
        role: input.role,
        storeId: input.role === Role.STORE ? input.storeId! : null,
        permissions: input.role === Role.MANAGER ? input.permissions ?? DEFAULT_MANAGER_PERMISSIONS : [],
      },
      select: { id: true },
    });

    if (input.role === Role.MANAGER && input.managedStoreIds?.length) {
      await tx.store.updateMany({ where: { id: { in: input.managedStoreIds } }, data: { assignedManagerId: user.id } });
    }

    const dto = toUserDto(await tx.user.findUniqueOrThrow({ where: { id: user.id }, select: userSelect }));
    await audit(tx, context, {
      action: 'CREATE',
      module: 'users',
      recordId: user.id,
      summary: `Created ${dto.role.toLowerCase()} user ${dto.name} (${dto.email})`,
      newValue: dto,
    });
    return dto;
  });
}

export async function updateUser(context: RequestContext, id: string, input: UpdateUser) {
  const existing = await prisma.user.findUnique({ where: { id }, select: userSelect });
  if (!existing) throw ApiError.notFound('User');
  assertCanManage(context, existing);

  if (input.status === RecordStatus.INACTIVE && id === context.user.id) {
    throw ApiError.badRequest('You cannot deactivate your own account');
  }
  if (input.storeId !== undefined && existing.role !== Role.STORE) {
    throw ApiError.validation([{ field: 'storeId', message: 'Only store users can be assigned to a store' }]);
  }
  if (existing.role === Role.STORE && input.storeId === null) {
    throw ApiError.validation([{ field: 'storeId', message: 'Store users must be assigned to a store' }]);
  }
  if (input.storeId && !isAdmin(context)) assertStoreAccess(context.scope, input.storeId);
  if (input.permissions && (existing.role !== Role.MANAGER || !isAdmin(context))) {
    throw ApiError.forbidden('Only admins can change manager permissions');
  }

  return prisma.$transaction(async (tx) => {
    if (input.storeId) await assertStoreExists(tx, input.storeId);

    const data: Prisma.UserUncheckedUpdateInput = { ...input };
    // Deactivation / store move must end existing sessions immediately.
    if ((input.status && input.status !== existing.status) || (input.storeId && input.storeId !== existing.storeId)) {
      data.tokenVersion = { increment: 1 };
      await tx.refreshToken.updateMany({ where: { userId: id, revokedAt: null }, data: { revokedAt: new Date() } });
    }
    await tx.user.update({ where: { id }, data });
    const updated = toUserDto(await tx.user.findUniqueOrThrow({ where: { id }, select: userSelect }));

    const { oldValue, newValue, changed } = diff(existing as unknown as Record<string, unknown>, input);
    if (changed) {
      await audit(tx, context, {
        action: 'UPDATE',
        module: 'users',
        recordId: id,
        summary: `Updated user ${updated.name}`,
        oldValue,
        newValue,
      });
    }
    return updated;
  });
}

/**
 * A user who has ever created a stock movement, sale, request, packing order,
 * transfer, or audit entry (i.e. done anything at all) can never be
 * hard-deleted - that history must stay attributable - so they are
 * deactivated instead. Only a completely unused account is removed.
 */
export async function deleteUser(context: RequestContext, id: string) {
  const existing = await prisma.user.findUnique({ where: { id }, select: userSelect });
  if (!existing) throw ApiError.notFound('User');
  assertCanManage(context, existing);
  if (id === context.user.id) throw ApiError.badRequest('You cannot delete your own account');

  const [managedStores, movements, sales, returns, requestsCreated, requestsReviewed, packingCreated, transfersReq, transfersApp, transfersDisp, transfersRecv, auditLogs] = await Promise.all([
    prisma.store.count({ where: { assignedManagerId: id } }),
    prisma.stockMovement.count({ where: { createdById: id } }),
    prisma.sale.count({ where: { createdById: id } }),
    prisma.saleReturn.count({ where: { createdById: id } }),
    prisma.productRequest.count({ where: { createdById: id } }),
    prisma.productRequest.count({ where: { reviewedById: id } }),
    prisma.packingOrder.count({ where: { createdById: id } }),
    prisma.stockTransfer.count({ where: { requestedById: id } }),
    prisma.stockTransfer.count({ where: { approvedById: id } }),
    prisma.stockTransfer.count({ where: { dispatchedById: id } }),
    prisma.stockTransfer.count({ where: { receivedById: id } }),
    prisma.auditLog.count({ where: { userId: id } }),
  ]);
  const hasHistory =
    managedStores + movements + sales + returns + requestsCreated + requestsReviewed + packingCreated + transfersReq + transfersApp + transfersDisp + transfersRecv + auditLogs > 0;

  if (hasHistory) {
    if (managedStores > 0) {
      throw ApiError.invalidState(`Reassign ${existing.name}'s ${managedStores} store(s) to another manager before removing this account.`);
    }
    await prisma.$transaction(async (tx) => {
      await tx.user.update({ where: { id }, data: { status: RecordStatus.INACTIVE, tokenVersion: { increment: 1 } } });
      await tx.refreshToken.updateMany({ where: { userId: id, revokedAt: null }, data: { revokedAt: new Date() } });
      await audit(tx, context, { action: 'DEACTIVATE', module: 'users', recordId: id, summary: `Deactivated ${existing.name} instead of deleting - the account has activity history` });
    });
    return { deleted: false, deactivated: true };
  }

  await prisma.$transaction(async (tx) => {
    await tx.user.delete({ where: { id } }); // cascades refresh/reset tokens and notifications
    await audit(tx, context, { action: 'DELETE', module: 'users', recordId: id, summary: `Deleted ${existing.role.toLowerCase()} ${existing.name} (${existing.email})` });
  });
  return { deleted: true, deactivated: false };
}

export async function adminResetPassword(context: RequestContext, id: string, newPassword: string) {
  const existing = await prisma.user.findUnique({ where: { id }, select: { id: true, name: true, role: true, storeId: true } });
  if (!existing) throw ApiError.notFound('User');
  assertCanManage(context, existing);
  const passwordHash = await hashPassword(newPassword);
  await prisma.$transaction(async (tx) => {
    await tx.user.update({ where: { id }, data: { passwordHash, tokenVersion: { increment: 1 } } });
    await tx.refreshToken.updateMany({ where: { userId: id, revokedAt: null }, data: { revokedAt: new Date() } });
    await audit(tx, context, { action: 'PASSWORD_RESET', module: 'users', recordId: id, summary: `Reset password for ${existing.name}` });
  });
}

// ─────────────── Managers ───────────────

export async function listManagers(q: UserListQuery) {
  const where = userRepository.buildWhere({ ...q, role: Role.MANAGER });
  const { rows, total } = await userRepository.list(where, q);
  return { rows: rows.map((u) => ({ ...toUserDto(u), managedStoreCount: u._count.managedStores })), total };
}

async function getManagerOrThrow(id: string) {
  const manager = await prisma.user.findUnique({ where: { id }, select: userSelect });
  if (!manager || manager.role !== Role.MANAGER) throw ApiError.notFound('Manager');
  return manager;
}

/** Replaces the full set of stores assigned to a manager. */
export async function setManagerStores(context: RequestContext, id: string, storeIds: string[]) {
  const manager = await getManagerOrThrow(id);
  const unique = [...new Set(storeIds)];
  return prisma.$transaction(async (tx) => {
    const found = await tx.store.count({ where: { id: { in: unique } } });
    if (found !== unique.length) throw ApiError.validation([{ field: 'storeIds', message: 'One or more stores do not exist' }]);

    await tx.store.updateMany({
      where: { assignedManagerId: id, id: { notIn: unique } },
      data: { assignedManagerId: null },
    });
    if (unique.length) {
      await tx.store.updateMany({ where: { id: { in: unique } }, data: { assignedManagerId: id } });
    }
    const updated = toUserDto(await tx.user.findUniqueOrThrow({ where: { id }, select: userSelect }));
    await audit(tx, context, {
      action: 'ASSIGN_STORES',
      module: 'managers',
      recordId: id,
      summary: `Assigned ${unique.length} store(s) to manager ${manager.name}`,
      oldValue: { stores: manager.managedStores.map((s) => s.code) },
      newValue: { stores: updated.managedStores.map((s) => s.code) },
    });
    return updated;
  });
}

export async function setManagerPermissions(context: RequestContext, id: string, permissions: string[]) {
  const manager = await getManagerOrThrow(id);
  const unique = [...new Set(permissions)];
  return prisma.$transaction(async (tx) => {
    await tx.user.update({ where: { id }, data: { permissions: unique } });
    await audit(tx, context, {
      action: 'UPDATE_PERMISSIONS',
      module: 'managers',
      recordId: id,
      summary: `Updated permissions for manager ${manager.name}`,
      oldValue: { permissions: manager.permissions },
      newValue: { permissions: unique },
    });
    return toUserDto(await tx.user.findUniqueOrThrow({ where: { id }, select: userSelect }));
  });
}
