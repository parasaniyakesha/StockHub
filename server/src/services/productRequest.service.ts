import { Prisma, ProductRequestStatus as S, RecordStatus, Role } from '@prisma/client';
import { z } from 'zod';
import { prisma, transaction, Tx } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { contains, dateRange, orderBy, pageArgs } from '../utils/pagination';
import { nextDocumentNumber } from '../utils/numbering';
import { assertRecordInScope, assertStoreAccess, storeFilter } from '../middleware/storeScope';
import { RequestContext } from '../types/auth';
import { audit } from './audit.service';
import { notify, NotificationType } from './notification.service';
import { approveRequestSchema, createRequestSchema, updateRequestSchema } from '../validators/operations.validator';
import { ListQuery } from '../validators/common.validator';

const detailInclude = {
  store: { select: { id: true, name: true, code: true } },
  items: {
    include: {
      product: { select: { id: true, name: true, sku: true, unit: true, sellingPrice: true } },
      allocations: {
        select: {
          id: true,
          allocatedQuantity: true,
          packedQuantity: true,
          dispatchedQuantity: true,
          receivedQuantity: true,
          damagedQuantity: true,
          packingOrderStore: { select: { status: true, packingOrder: { select: { id: true, orderNumber: true, status: true } } } },
        },
      },
    },
    orderBy: { product: { name: 'asc' } },
  },
  packingOrders: { select: { packingOrder: { select: { id: true, orderNumber: true, status: true } }, status: true } },
} satisfies Prisma.ProductRequestInclude;

export const REVIEWABLE: S[] = [S.SUBMITTED, S.UNDER_REVIEW];
export const PACKABLE: S[] = [S.APPROVED, S.PARTIALLY_APPROVED];

const userName = async (id: string | null) =>
  id ? (await prisma.user.findUnique({ where: { id }, select: { name: true } }))?.name ?? null : null;

export async function listRequests(context: RequestContext, q: ListQuery) {
  const search = contains(q.search);
  const where: Prisma.ProductRequestWhereInput = {
    ...(storeFilter(context.scope, q.storeId) ? { storeId: storeFilter(context.scope, q.storeId) } : {}),
    ...(q.status ? { status: { in: q.status.split(',') as S[] } } : {}),
    ...(dateRange(q) ? { createdAt: dateRange(q) } : {}),
    ...(q.productId ? { items: { some: { productId: q.productId } } } : {}),
    ...(search ? { OR: [{ requestNumber: search }, { store: { name: search } }, { notes: search }] } : {}),
  };
  const [rows, total] = await Promise.all([
    prisma.productRequest.findMany({
      where,
      include: {
        store: { select: { id: true, name: true, code: true } },
        _count: { select: { items: true } },
        items: { select: { requestedQuantity: true, approvedQuantity: true } },
      },
      orderBy: orderBy(q, {
        requestNumber: (d) => ({ requestNumber: d }),
        status: (d) => ({ status: d }),
        store: (d) => ({ store: { name: d } }),
        createdAt: (d) => ({ createdAt: d }),
        submittedAt: (d) => ({ submittedAt: { sort: d, nulls: 'last' } }),
      }, { createdAt: 'desc' }),
      ...pageArgs(q),
    }),
    prisma.productRequest.count({ where }),
  ]);
  return {
    rows: rows.map(({ items, ...r }) => ({
      ...r,
      itemCount: r._count.items,
      totalRequested: items.reduce((a, i) => a + i.requestedQuantity, 0),
      totalApproved: items.some((i) => i.approvedQuantity !== null) ? items.reduce((a, i) => a + (i.approvedQuantity ?? 0), 0) : null,
    })),
    total,
  };
}

async function loadInScope(context: RequestContext, id: string, db: Tx | typeof prisma = prisma) {
  const request = await db.productRequest.findUnique({ where: { id }, include: detailInclude });
  if (!request) throw ApiError.notFound('Product request');
  assertRecordInScope(context.scope, [request.storeId], 'Product request');
  return request;
}

export async function getRequest(context: RequestContext, id: string) {
  const request = await loadInScope(context, id);
  const [createdBy, reviewedBy] = await Promise.all([userName(request.createdById), userName(request.reviewedById)]);
  return {
    ...request,
    createdByName: createdBy,
    reviewedByName: reviewedBy,
    items: request.items.map((item) => {
      const active = item.allocations.filter((a) => a.packingOrderStore.status !== 'CANCELLED');
      const received = active.reduce((a, x) => a + x.receivedQuantity, 0);
      return {
        ...item,
        packedQuantity: active.reduce((a, x) => a + x.packedQuantity, 0),
        dispatchedQuantity: active.reduce((a, x) => a + x.dispatchedQuantity, 0),
        receivedQuantity: received,
        pendingQuantity: Math.max((item.approvedQuantity ?? 0) - received, 0),
      };
    }),
  };
}

async function assertActiveProducts(tx: Tx, productIds: string[]) {
  const products = await tx.product.findMany({ where: { id: { in: productIds } }, select: { id: true, name: true, status: true } });
  if (products.length !== productIds.length) throw ApiError.validation([{ field: 'items', message: 'One or more products do not exist' }]);
  const inactive = products.find((p) => p.status !== RecordStatus.ACTIVE);
  if (inactive) throw ApiError.validation([{ field: 'items', message: `${inactive.name} is not available for request` }]);
}

async function notifySubmitted(tx: Tx, context: RequestContext, request: { id: string; requestNumber: string; storeId: string }) {
  const store = await tx.store.findUniqueOrThrow({ where: { id: request.storeId }, select: { name: true } });
  await notify(tx, {
    type: NotificationType.REQUEST_SUBMITTED,
    title: 'Product request submitted',
    message: `${store.name} submitted product request ${request.requestNumber}.`,
    entityType: 'PRODUCT_REQUEST',
    entityId: request.id,
    admins: true,
    storeIds: [request.storeId],
    managersOnly: true,
    excludeUserId: context.user.id,
  });
}

export async function createRequest(context: RequestContext, input: z.infer<typeof createRequestSchema>) {
  const storeId = context.user.role === Role.STORE ? context.user.storeId! : input.storeId;
  if (!storeId) throw ApiError.validation([{ field: 'storeId', message: 'Select a store' }]);
  assertStoreAccess(context.scope, storeId);

  if (input.clientRequestId) {
    const existing = await prisma.productRequest.findUnique({ where: { clientRequestId: input.clientRequestId } });
    if (existing) return loadInScope(context, existing.id);
  }

  const id = await transaction(async (tx) => {
    const store = await tx.store.findUnique({ where: { id: storeId }, select: { status: true } });
    if (!store) throw ApiError.notFound('Store');
    if (store.status !== RecordStatus.ACTIVE) throw ApiError.invalidState('Store is inactive');
    await assertActiveProducts(tx, input.items.map((i) => i.productId));

    const request = await tx.productRequest.create({
      data: {
        requestNumber: await nextDocumentNumber(tx, 'REQ'),
        storeId,
        notes: input.notes,
        clientRequestId: input.clientRequestId,
        createdById: context.user.id,
        status: input.submit ? S.SUBMITTED : S.DRAFT,
        submittedAt: input.submit ? new Date() : null,
        items: { create: input.items.map((i) => ({ productId: i.productId, requestedQuantity: i.requestedQuantity, notes: i.notes })) },
      },
    });
    await audit(tx, context, {
      action: 'CREATE',
      module: 'product_requests',
      recordId: request.id,
      summary: `Created product request ${request.requestNumber}${input.submit ? ' and submitted it' : ' as draft'}`,
      newValue: input.items,
    });
    if (input.submit) await notifySubmitted(tx, context, request);
    return request.id;
  });
  return loadInScope(context, id);
}

export async function updateRequest(context: RequestContext, id: string, input: z.infer<typeof updateRequestSchema>) {
  await transaction(async (tx) => {
    const request = await loadInScope(context, id, tx);
    if (request.status !== S.DRAFT) throw ApiError.invalidState('Only draft requests can be edited');
    if (input.items) {
      await assertActiveProducts(tx, input.items.map((i) => i.productId));
      await tx.productRequestItem.deleteMany({ where: { requestId: id } });
      await tx.productRequestItem.createMany({
        data: input.items.map((i) => ({ requestId: id, productId: i.productId, requestedQuantity: i.requestedQuantity, notes: i.notes })),
      });
    }
    await tx.productRequest.update({ where: { id }, data: { notes: input.notes } });
    await audit(tx, context, {
      action: 'UPDATE',
      module: 'product_requests',
      recordId: id,
      summary: `Updated draft request ${request.requestNumber}`,
      oldValue: request.items.map((i) => ({ productId: i.productId, requestedQuantity: i.requestedQuantity })),
      newValue: input.items,
    });
  });
  return loadInScope(context, id);
}

/** Atomically moves a request from one of `from` to `to`; fails if another user got there first. */
async function transition(tx: Tx, id: string, from: S[], data: Prisma.ProductRequestUpdateManyMutationInput) {
  const result = await tx.productRequest.updateMany({ where: { id, status: { in: from } }, data });
  if (!result.count) throw ApiError.invalidState('This request is no longer in a state that allows this action');
}

export async function submitRequest(context: RequestContext, id: string) {
  await transaction(async (tx) => {
    const request = await loadInScope(context, id, tx);
    if (!request.items.length) throw ApiError.invalidState('Add at least one product before submitting');
    await transition(tx, id, [S.DRAFT], { status: S.SUBMITTED, submittedAt: new Date() });
    await audit(tx, context, { action: 'SUBMIT', module: 'product_requests', recordId: id, summary: `Submitted request ${request.requestNumber}` });
    await notifySubmitted(tx, context, request);
  });
  return loadInScope(context, id);
}

export async function startReview(context: RequestContext, id: string) {
  await transaction(async (tx) => {
    const request = await loadInScope(context, id, tx);
    await transition(tx, id, [S.SUBMITTED], { status: S.UNDER_REVIEW, reviewedById: context.user.id });
    await audit(tx, context, { action: 'REVIEW', module: 'product_requests', recordId: id, summary: `Started review of ${request.requestNumber}` });
  });
  return loadInScope(context, id);
}

export async function approveRequest(context: RequestContext, id: string, input: z.infer<typeof approveRequestSchema>) {
  await transaction(async (tx) => {
    const request = await loadInScope(context, id, tx);
    if (!REVIEWABLE.includes(request.status)) throw ApiError.invalidState('Only submitted requests can be approved');

    const byId = new Map(input.items.map((i) => [i.itemId, i.approvedQuantity]));
    const errors: { field: string; message: string }[] = [];
    request.items.forEach((item, index) => {
      const approved = byId.get(item.id);
      if (approved === undefined) errors.push({ field: `items.${index}.approvedQuantity`, message: `Enter the approved quantity for ${item.product.name}` });
      else if (approved > item.requestedQuantity) {
        errors.push({ field: `items.${index}.approvedQuantity`, message: `Approved quantity for ${item.product.name} cannot exceed requested (${item.requestedQuantity})` });
      }
    });
    if (input.items.some((i) => !request.items.find((x) => x.id === i.itemId))) {
      errors.push({ field: 'items', message: 'Item does not belong to this request' });
    }
    if (errors.length) throw ApiError.validation(errors);

    const totalApproved = request.items.reduce((a, i) => a + byId.get(i.id)!, 0);
    if (totalApproved === 0) throw ApiError.badRequest('Nothing was approved. Reject the request instead.');
    const full = request.items.every((i) => byId.get(i.id) === i.requestedQuantity);
    const status = full ? S.APPROVED : S.PARTIALLY_APPROVED;

    for (const item of request.items) {
      await tx.productRequestItem.update({ where: { id: item.id }, data: { approvedQuantity: byId.get(item.id)! } });
    }
    await transition(tx, id, REVIEWABLE, { status, reviewNotes: input.reviewNotes, reviewedById: context.user.id, reviewedAt: new Date() });

    await audit(tx, context, {
      action: 'APPROVE',
      module: 'product_requests',
      recordId: id,
      summary: `${context.user.role === Role.MANAGER ? 'Manager' : 'Admin'} ${context.user.name} ${full ? 'approved' : 'partially approved'} ${request.store.name} request ${request.requestNumber}`,
      oldValue: request.items.map((i) => ({ product: i.product.sku, requested: i.requestedQuantity })),
      newValue: request.items.map((i) => ({ product: i.product.sku, approved: byId.get(i.id) })),
    });
    await notify(tx, {
      type: NotificationType.REQUEST_APPROVED,
      title: 'Product request approved',
      message: `Request ${request.requestNumber} was ${full ? 'approved' : 'partially approved'} (${totalApproved} units).`,
      entityType: 'PRODUCT_REQUEST',
      entityId: id,
      storeIds: [request.storeId],
      admins: context.user.role !== Role.ADMIN,
      excludeUserId: context.user.id,
    });
  });
  return loadInScope(context, id);
}

export async function rejectRequest(context: RequestContext, id: string, reason: string) {
  await transaction(async (tx) => {
    const request = await loadInScope(context, id, tx);
    await transition(tx, id, REVIEWABLE, { status: S.REJECTED, reviewNotes: reason, reviewedById: context.user.id, reviewedAt: new Date() });
    await tx.productRequestItem.updateMany({ where: { requestId: id }, data: { approvedQuantity: 0 } });
    await audit(tx, context, { action: 'REJECT', module: 'product_requests', recordId: id, summary: `Rejected request ${request.requestNumber}: ${reason}` });
    await notify(tx, {
      type: NotificationType.REQUEST_REJECTED,
      title: 'Product request rejected',
      message: `Request ${request.requestNumber} was rejected: ${reason}`,
      entityType: 'PRODUCT_REQUEST',
      entityId: id,
      storeIds: [request.storeId],
      excludeUserId: context.user.id,
    });
  });
  return loadInScope(context, id);
}

export async function cancelRequest(context: RequestContext, id: string, reason?: string) {
  await transaction(async (tx) => {
    const request = await loadInScope(context, id, tx);
    const cancellable: S[] = context.user.role === Role.STORE ? [S.DRAFT, S.SUBMITTED] : [S.DRAFT, S.SUBMITTED, S.UNDER_REVIEW, ...PACKABLE];
    const linked = request.packingOrders.some((p) => p.status !== 'CANCELLED');
    if (linked) throw ApiError.invalidState('This request is already part of a packing order');
    await transition(tx, id, cancellable, { status: S.CANCELLED, reviewNotes: reason ?? request.reviewNotes });
    await audit(tx, context, { action: 'CANCEL', module: 'product_requests', recordId: id, summary: `Cancelled request ${request.requestNumber}${reason ? `: ${reason}` : ''}` });
  });
  return loadInScope(context, id);
}

/** Called by the packing order workflow to keep linked requests in sync. */
export async function syncRequestStatus(tx: Tx, requestIds: (string | null)[], status: S) {
  const ids = requestIds.filter((x): x is string => Boolean(x));
  if (ids.length) await tx.productRequest.updateMany({ where: { id: { in: ids } }, data: { status } });
}

/** When a packing order is cancelled, linked requests fall back to their approval status. */
export async function revertRequestsToApproved(tx: Tx, requestIds: (string | null)[]) {
  const ids = requestIds.filter((x): x is string => Boolean(x));
  for (const id of ids) {
    const items = await tx.productRequestItem.findMany({ where: { requestId: id }, select: { requestedQuantity: true, approvedQuantity: true } });
    const full = items.every((i) => i.approvedQuantity === i.requestedQuantity);
    await tx.productRequest.update({ where: { id }, data: { status: full ? S.APPROVED : S.PARTIALLY_APPROVED } });
  }
}
