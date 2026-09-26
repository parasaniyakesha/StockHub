import { LocationType, MovementType, Prisma, RecordStatus, Role, StockBucket, TransferStatus as S } from '@prisma/client';
import { z } from 'zod';
import { prisma, transaction, Tx } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { contains, dateRange, orderBy, pageArgs } from '../utils/pagination';
import { nextDocumentNumber } from '../utils/numbering';
import { assertStoreAccess, canAccessStore } from '../middleware/storeScope';
import { hasPermission } from '../middleware/authorize';
import { PERMISSIONS } from '../config/permissions';
import { RequestContext } from '../types/auth';
import { applyMovement, ReferenceType, releaseReservation, reserve, StockLocation } from './stockLedger.service';
import { audit } from './audit.service';
import { notify, NotificationType } from './notification.service';
import { resolveWarehouse } from './warehouse.service';
import { approveTransferSchema, createTransferSchema, receiveLinesSchema, transferListQuery } from '../validators/operations.validator';

/**
 * Transfer lifecycle and stock effect:
 *   REQUESTED   nothing moves
 *   APPROVED    source stock RESERVED (approved quantities)
 *   DISPATCHED  source: TRANSFER_OUT (-), reservation released; goods in transit
 *   RECEIVED    destination: TRANSFER_IN (+) received / damaged, but with a discrepancy (needs closing)
 *   COMPLETED   received exactly as dispatched, or closed after a discrepancy
 *   REJECTED / CANCELLED  reservation (if any) released
 */

const include = {
  fromWarehouse: { select: { id: true, name: true, code: true } },
  fromStore: { select: { id: true, name: true, code: true } },
  toStore: { select: { id: true, name: true, code: true } },
  items: { include: { product: { select: { id: true, name: true, sku: true, unit: true } } }, orderBy: { product: { name: 'asc' } } },
} satisfies Prisma.StockTransferInclude;

type Transfer = Prisma.StockTransferGetPayload<{ include: typeof include }>;

const sourceOf = (t: { sourceType: LocationType; fromWarehouseId: string | null; fromStoreId: string | null }): StockLocation =>
  t.sourceType === LocationType.WAREHOUSE ? { kind: 'WAREHOUSE', warehouseId: t.fromWarehouseId! } : { kind: 'STORE', storeId: t.fromStoreId! };

const sourceName = (t: Transfer) => (t.sourceType === LocationType.WAREHOUSE ? t.fromWarehouse?.name ?? 'Warehouse' : t.fromStore?.name ?? 'Store');

const isAdmin = (c: RequestContext) => c.user.role === Role.ADMIN;

/** Admin: always. Manager: needs the permission and access to the relevant store. Store: only its own store. */
function canActOn(context: RequestContext, storeId: string | null, permission: (typeof PERMISSIONS)[keyof typeof PERMISSIONS]) {
  if (isAdmin(context)) return true;
  if (!storeId || !canAccessStore(context.scope, storeId)) return false;
  return hasPermission(context, permission);
}

async function loadInScope(context: RequestContext, id: string, db: Tx | typeof prisma = prisma) {
  const transfer = await db.stockTransfer.findUnique({ where: { id }, include });
  if (!transfer) throw ApiError.notFound('Transfer');
  if (!isAdmin(context) && !canAccessStore(context.scope, transfer.toStoreId) && !canAccessStore(context.scope, transfer.fromStoreId)) {
    throw ApiError.notFound('Transfer');
  }
  return transfer;
}

function present(context: RequestContext, t: Transfer) {
  const src = t.sourceType === LocationType.WAREHOUSE ? null : t.fromStoreId;
  return {
    ...t,
    items: t.items.map((i) => ({
      ...i,
      shortQuantity: t.status === S.RECEIVED || t.status === S.COMPLETED ? Math.max(i.dispatchedQuantity - i.receivedQuantity - i.damagedQuantity, 0) : 0,
    })),
    // Hints for the UI - the server re-checks every action.
    allowedActions: {
      approve: t.status === S.REQUESTED && (t.sourceType === LocationType.WAREHOUSE ? isAdmin(context) : canActOn(context, src, PERMISSIONS.TRANSFERS_APPROVE) && context.user.role !== Role.STORE),
      reject: t.status === S.REQUESTED && (t.sourceType === LocationType.WAREHOUSE ? isAdmin(context) : canActOn(context, src, PERMISSIONS.TRANSFERS_APPROVE) && context.user.role !== Role.STORE),
      dispatch: t.status === S.APPROVED && (t.sourceType === LocationType.WAREHOUSE ? isAdmin(context) : canActOn(context, src, PERMISSIONS.TRANSFERS_DISPATCH)),
      receive: t.status === S.DISPATCHED && canActOn(context, t.toStoreId, PERMISSIONS.TRANSFERS_RECEIVE),
      complete: t.status === S.RECEIVED && context.user.role !== Role.STORE && (isAdmin(context) || canAccessStore(context.scope, t.toStoreId)),
      cancel: (t.status === S.REQUESTED || t.status === S.APPROVED) && (isAdmin(context) || t.requestedById === context.user.id),
    },
  };
}

export async function getTransfer(context: RequestContext, id: string) {
  return present(context, await loadInScope(context, id));
}

export async function listTransfers(context: RequestContext, q: z.infer<typeof transferListQuery>) {
  const search = contains(q.search);
  const and: Prisma.StockTransferWhereInput[] = [];

  if (q.storeId) {
    assertStoreAccess(context.scope, q.storeId);
    and.push(q.direction === 'IN' ? { toStoreId: q.storeId } : q.direction === 'OUT' ? { fromStoreId: q.storeId } : { OR: [{ toStoreId: q.storeId }, { fromStoreId: q.storeId }] });
  } else if (!context.scope.all) {
    const ids = context.scope.storeIds;
    and.push(q.direction === 'IN' ? { toStoreId: { in: ids } } : q.direction === 'OUT' ? { fromStoreId: { in: ids } } : { OR: [{ toStoreId: { in: ids } }, { fromStoreId: { in: ids } }] });
  }
  if (q.status) and.push({ status: { in: q.status.split(',') as S[] } });
  if (q.sourceType) and.push({ sourceType: q.sourceType as LocationType });
  if (dateRange(q)) and.push({ createdAt: dateRange(q) });
  if (q.productId) and.push({ items: { some: { productId: q.productId } } });
  if (search) and.push({ OR: [{ transferNumber: search }, { toStore: { name: search } }, { fromStore: { name: search } }, { notes: search }] });

  const where: Prisma.StockTransferWhereInput = { AND: and };
  const [rows, total] = await Promise.all([
    prisma.stockTransfer.findMany({
      where,
      include: { ...include, items: { select: { requestedQuantity: true, approvedQuantity: true, dispatchedQuantity: true, receivedQuantity: true } } },
      orderBy: orderBy(q, {
        transferNumber: (d) => ({ transferNumber: d }),
        status: (d) => ({ status: d }),
        createdAt: (d) => ({ createdAt: d }),
        toStore: (d) => ({ toStore: { name: d } }),
      }, { createdAt: 'desc' }),
      ...pageArgs(q),
    }),
    prisma.stockTransfer.count({ where }),
  ]);
  return {
    rows: rows.map(({ items, ...t }) => ({
      ...t,
      itemCount: items.length,
      totalRequested: items.reduce((a, i) => a + i.requestedQuantity, 0),
      totalDispatched: items.reduce((a, i) => a + i.dispatchedQuantity, 0),
      totalReceived: items.reduce((a, i) => a + i.receivedQuantity, 0),
    })),
    total,
  };
}

export async function createTransfer(context: RequestContext, input: z.infer<typeof createTransferSchema>) {
  if (input.clientRequestId) {
    const existing = await prisma.stockTransfer.findUnique({ where: { clientRequestId: input.clientRequestId }, select: { id: true } });
    if (existing) return getTransfer(context, existing.id);
  }

  // A store may request stock into itself or offer stock out of itself.
  if (!isAdmin(context)) {
    const touchesScope = canAccessStore(context.scope, input.toStoreId) || (input.fromStoreId && canAccessStore(context.scope, input.fromStoreId));
    if (!touchesScope) throw ApiError.forbidden('You can only create transfers involving your own store(s)');
    if (input.sourceType === 'WAREHOUSE' && !canAccessStore(context.scope, input.toStoreId)) throw ApiError.forbidden();
  }

  const id = await transaction(async (tx) => {
    const storeIds = [input.toStoreId, input.fromStoreId].filter((x): x is string => Boolean(x));
    const stores = await tx.store.findMany({ where: { id: { in: storeIds } }, select: { id: true, name: true, status: true } });
    if (stores.length !== storeIds.length) throw ApiError.validation([{ field: 'toStoreId', message: 'Store does not exist' }]);
    const inactive = stores.find((s) => s.status !== RecordStatus.ACTIVE);
    if (inactive) throw ApiError.invalidState(`${inactive.name} is inactive`);

    const warehouseId = input.sourceType === 'WAREHOUSE' ? (await resolveWarehouse(tx, input.fromWarehouseId)).id : null;
    const products = await tx.product.findMany({ where: { id: { in: input.items.map((i) => i.productId) } }, select: { id: true, name: true, status: true } });
    if (products.length !== input.items.length) throw ApiError.validation([{ field: 'items', message: 'One or more products do not exist' }]);
    const inactiveProduct = products.find((p) => p.status !== RecordStatus.ACTIVE);
    if (inactiveProduct) throw ApiError.validation([{ field: 'items', message: `${inactiveProduct.name} is inactive` }]);

    const transfer = await tx.stockTransfer.create({
      data: {
        transferNumber: await nextDocumentNumber(tx, 'TR'),
        sourceType: input.sourceType as LocationType,
        fromWarehouseId: warehouseId,
        fromStoreId: input.sourceType === 'STORE' ? input.fromStoreId! : null,
        toStoreId: input.toStoreId,
        notes: input.notes,
        clientRequestId: input.clientRequestId,
        requestedById: context.user.id,
        items: { create: input.items.map((i) => ({ productId: i.productId, requestedQuantity: i.quantity })) },
      },
      include,
    });
    await audit(tx, context, {
      action: 'CREATE',
      module: 'transfers',
      recordId: transfer.id,
      summary: `Requested transfer ${transfer.transferNumber} from ${sourceName(transfer)} to ${transfer.toStore.name}`,
      newValue: input.items,
    });
    await notify(tx, {
      type: NotificationType.TRANSFER_REQUESTED,
      title: 'Transfer requested',
      message: `Transfer ${transfer.transferNumber} requested from ${sourceName(transfer)} to ${transfer.toStore.name}.`,
      entityType: 'TRANSFER',
      entityId: transfer.id,
      admins: true,
      storeIds: storeIds,
      excludeUserId: context.user.id,
    });
    return transfer.id;
  });
  return getTransfer(context, id);
}

async function transition(tx: Tx, id: string, from: S[], data: Prisma.StockTransferUpdateManyMutationInput) {
  const result = await tx.stockTransfer.updateMany({ where: { id, status: { in: from } }, data });
  if (!result.count) throw ApiError.invalidState('This transfer is no longer in a state that allows this action');
}

function assertApprover(context: RequestContext, t: Transfer) {
  if (context.user.role === Role.STORE) throw ApiError.forbidden('Store users cannot approve transfers');
  const ok = t.sourceType === LocationType.WAREHOUSE ? isAdmin(context) : canActOn(context, t.fromStoreId, PERMISSIONS.TRANSFERS_APPROVE);
  if (!ok) throw ApiError.forbidden('You are not allowed to approve this transfer');
}

export async function approveTransfer(context: RequestContext, id: string, input: z.infer<typeof approveTransferSchema>) {
  await transaction(async (tx) => {
    const t = await loadInScope(context, id, tx);
    assertApprover(context, t);
    const approved = new Map(input.items?.map((i) => [i.itemId, i.approvedQuantity]) ?? []);
    const errors: { field: string; message: string }[] = [];
    t.items.forEach((item, idx) => {
      const qty = approved.get(item.id) ?? item.requestedQuantity;
      if (qty > item.requestedQuantity) errors.push({ field: `items.${idx}.approvedQuantity`, message: `${item.product.name}: approved cannot exceed requested (${item.requestedQuantity})` });
    });
    if (errors.length) throw ApiError.validation(errors);
    const total = t.items.reduce((a, i) => a + (approved.get(i.id) ?? i.requestedQuantity), 0);
    if (total === 0) throw ApiError.badRequest('Nothing was approved. Reject the transfer instead.');

    await transition(tx, id, [S.REQUESTED], { status: S.APPROVED, approvedById: context.user.id, approvedAt: new Date() });
    const source = sourceOf(t);
    for (const item of t.items) {
      const qty = approved.get(item.id) ?? item.requestedQuantity;
      await tx.stockTransferItem.update({ where: { id: item.id }, data: { approvedQuantity: qty } });
      await reserve(tx, source, item.productId, qty);
    }
    await audit(tx, context, {
      action: 'APPROVE',
      module: 'transfers',
      recordId: id,
      summary: `Approved transfer ${t.transferNumber} (${total} units)`,
      newValue: t.items.map((i) => ({ productId: i.productId, approved: approved.get(i.id) ?? i.requestedQuantity })),
    });
    await notify(tx, {
      type: NotificationType.TRANSFER_APPROVED,
      title: 'Transfer approved',
      message: `Transfer ${t.transferNumber} to ${t.toStore.name} was approved.`,
      entityType: 'TRANSFER',
      entityId: id,
      storeIds: [t.toStoreId, t.fromStoreId].filter((x): x is string => Boolean(x)),
      excludeUserId: context.user.id,
    });
  });
  return getTransfer(context, id);
}

export async function rejectTransfer(context: RequestContext, id: string, reason: string) {
  await transaction(async (tx) => {
    const t = await loadInScope(context, id, tx);
    assertApprover(context, t);
    await transition(tx, id, [S.REQUESTED], { status: S.REJECTED, rejectionReason: reason, approvedById: context.user.id });
    await audit(tx, context, { action: 'REJECT', module: 'transfers', recordId: id, summary: `Rejected transfer ${t.transferNumber}: ${reason}` });
    await notify(tx, {
      type: NotificationType.TRANSFER_REJECTED,
      title: 'Transfer rejected',
      message: `Transfer ${t.transferNumber} was rejected: ${reason}`,
      entityType: 'TRANSFER',
      entityId: id,
      userIds: [t.requestedById],
      storeIds: [t.toStoreId],
      excludeUserId: context.user.id,
    });
  });
  return getTransfer(context, id);
}

export async function dispatchTransfer(context: RequestContext, id: string) {
  await transaction(async (tx) => {
    const t = await loadInScope(context, id, tx);
    const ok = t.sourceType === LocationType.WAREHOUSE ? isAdmin(context) : canActOn(context, t.fromStoreId, PERMISSIONS.TRANSFERS_DISPATCH);
    if (!ok) throw ApiError.forbidden('Only the source location can dispatch this transfer');
    await transition(tx, id, [S.APPROVED], { status: S.DISPATCHED, dispatchedById: context.user.id, dispatchedAt: new Date() });
    const source = sourceOf(t);
    for (const item of t.items) {
      const qty = item.approvedQuantity ?? 0;
      await tx.stockTransferItem.update({ where: { id: item.id }, data: { dispatchedQuantity: qty } });
      if (qty > 0) {
        await applyMovement(tx, {
          location: source,
          productId: item.productId,
          type: MovementType.TRANSFER_OUT,
          quantity: -qty,
          releaseReserved: qty,
          referenceType: ReferenceType.TRANSFER,
          referenceId: id,
          reason: `Transfer ${t.transferNumber} to ${t.toStore.name}`,
          userId: context.user.id,
        });
      }
    }
    await audit(tx, context, { action: 'DISPATCH', module: 'transfers', recordId: id, summary: `Dispatched transfer ${t.transferNumber}` });
    await notify(tx, {
      type: NotificationType.TRANSFER_DISPATCHED,
      title: 'Transfer dispatched',
      message: `Transfer ${t.transferNumber} from ${sourceName(t)} is on its way.`,
      entityType: 'TRANSFER',
      entityId: id,
      storeIds: [t.toStoreId],
      excludeUserId: context.user.id,
    });
  });
  return getTransfer(context, id);
}

export async function receiveTransfer(context: RequestContext, id: string, input: z.infer<typeof receiveLinesSchema>) {
  await transaction(async (tx) => {
    const t = await loadInScope(context, id, tx);
    if (!canActOn(context, t.toStoreId, PERMISSIONS.TRANSFERS_RECEIVE)) throw ApiError.forbidden('Only the destination store can receive this transfer');
    if (t.status !== S.DISPATCHED) throw ApiError.invalidState('Only dispatched transfers can be received');

    const lines = new Map(input.lines?.map((l) => [l.id, l]) ?? []);
    if (input.lines?.some((l) => !t.items.find((i) => i.id === l.id))) {
      throw ApiError.validation([{ field: 'lines', message: 'Line does not belong to this transfer' }]);
    }
    let discrepancy = false;
    const plans = t.items.map((item) => {
      const l = lines.get(item.id);
      const received = l?.receivedQuantity ?? item.dispatchedQuantity;
      const damaged = l?.damagedQuantity ?? 0;
      if (received + damaged > item.dispatchedQuantity) {
        throw ApiError.validation([{ field: `lines.${item.id}`, message: `${item.product.name}: received + damaged exceeds dispatched (${item.dispatchedQuantity})` }]);
      }
      if (received + damaged !== item.dispatchedQuantity || damaged > 0) discrepancy = true;
      return { item, received, damaged };
    });

    await transition(tx, id, [S.DISPATCHED], {
      status: discrepancy ? S.RECEIVED : S.COMPLETED,
      receivedById: context.user.id,
      receivedAt: new Date(),
      ...(discrepancy ? {} : { completedAt: new Date() }),
      ...(input.notes ? { notes: `${t.notes ? `${t.notes}\n` : ''}Receipt: ${input.notes}` } : {}),
    });

    const dest: StockLocation = { kind: 'STORE', storeId: t.toStoreId };
    for (const { item, received, damaged } of plans) {
      await tx.stockTransferItem.update({ where: { id: item.id }, data: { receivedQuantity: received, damagedQuantity: damaged } });
      const common = { location: dest, productId: item.productId, type: MovementType.TRANSFER_IN, referenceType: ReferenceType.TRANSFER, referenceId: id, userId: context.user.id };
      if (received > 0) await applyMovement(tx, { ...common, quantity: received, reason: `Transfer ${t.transferNumber} from ${sourceName(t)}` });
      if (damaged > 0) await applyMovement(tx, { ...common, bucket: StockBucket.DAMAGED, quantity: damaged, reason: `Damaged in transfer ${t.transferNumber}` });
    }
    await audit(tx, context, {
      action: 'RECEIVE',
      module: 'transfers',
      recordId: id,
      summary: `${t.toStore.name} received transfer ${t.transferNumber}${discrepancy ? ' with discrepancies' : ''}`,
      newValue: plans.map((p) => ({ productId: p.item.productId, dispatched: p.item.dispatchedQuantity, received: p.received, damaged: p.damaged })),
    });
    await notify(tx, {
      type: NotificationType.TRANSFER_RECEIVED,
      title: 'Transfer received',
      message: `${t.toStore.name} received transfer ${t.transferNumber}${discrepancy ? ' with discrepancies' : ''}.`,
      entityType: 'TRANSFER',
      entityId: id,
      admins: true,
      storeIds: [t.fromStoreId, t.toStoreId].filter((x): x is string => Boolean(x)),
      excludeUserId: context.user.id,
    });
  });
  return getTransfer(context, id);
}

export async function completeTransfer(context: RequestContext, id: string) {
  await transaction(async (tx) => {
    const t = await loadInScope(context, id, tx);
    if (context.user.role === Role.STORE) throw ApiError.forbidden();
    await transition(tx, id, [S.RECEIVED], { status: S.COMPLETED, completedAt: new Date() });
    await audit(tx, context, { action: 'COMPLETE', module: 'transfers', recordId: id, summary: `Closed transfer ${t.transferNumber} after discrepancy review` });
  });
  return getTransfer(context, id);
}

export async function cancelTransfer(context: RequestContext, id: string, reason?: string) {
  await transaction(async (tx) => {
    const t = await loadInScope(context, id, tx);
    if (!isAdmin(context) && t.requestedById !== context.user.id) throw ApiError.forbidden('Only the requester or an admin can cancel');
    if (t.status !== S.REQUESTED && t.status !== S.APPROVED) throw ApiError.invalidState('Only pending transfers can be cancelled');
    // Transition from the exact status read so the reservation release below matches reality.
    await transition(tx, id, [t.status], { status: S.CANCELLED, rejectionReason: reason });
    if (t.status === S.APPROVED) {
      for (const item of t.items) await releaseReservation(tx, sourceOf(t), item.productId, item.approvedQuantity ?? 0);
    }
    await audit(tx, context, { action: 'CANCEL', module: 'transfers', recordId: id, summary: `Cancelled transfer ${t.transferNumber}${reason ? `: ${reason}` : ''}` });
  });
  return getTransfer(context, id);
}
