import {
  MovementType,
  PackingOrderStatus as S,
  PackingStoreStatus,
  Prisma,
  ProductRequestStatus,
  RecordStatus,
  Role,
  StockBucket,
} from '@prisma/client';
import { z } from 'zod';
import { prisma, transaction, Tx } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { contains, dateRange, orderBy, pageArgs } from '../utils/pagination';
import { nextDocumentNumber } from '../utils/numbering';
import { assertStoreAccess, canAccessStore } from '../middleware/storeScope';
import { RequestContext } from '../types/auth';
import { ListQuery } from '../validators/common.validator';
import {
  createPackingOrderSchema,
  packingFromRequestsSchema,
  packSchema,
  receiveLinesSchema,
  updatePackingOrderSchema,
} from '../validators/operations.validator';
import { applyMovement, ReferenceType, releaseReservation, reserve } from './stockLedger.service';
import { audit } from './audit.service';
import { notify, NotificationType } from './notification.service';
import { resolveWarehouse } from './warehouse.service';
import { PACKABLE, revertRequestsToApproved, syncRequestStatus } from './productRequest.service';

/**
 * Packing order lifecycle and where stock moves:
 *   DRAFT      editable; nothing reserved
 *   ASSIGNED   allocations frozen; warehouse stock RESERVED (no movement)
 *   PACKING    work in progress
 *   PACKED     packed quantities leave the warehouse: PACKING movement (-), reservation released
 *   DISPATCHED goods in transit to each store
 *   (per store) RECEIVED  store stock += received: TRANSFER_IN movement (+), damaged into DAMAGED bucket
 *   RECEIVED   all stores received but at least one had a discrepancy (awaiting admin close)
 *   COMPLETED  all stores received with no discrepancy, or closed by admin
 *   CANCELLED  reservations released; packed goods returned to warehouse (CANCELLATION +)
 */

type CreateInput = z.infer<typeof createPackingOrderSchema>;

const detailInclude = {
  warehouse: { select: { id: true, name: true, code: true } },
  items: { include: { product: { select: { id: true, name: true, sku: true, unit: true } } }, orderBy: { product: { name: 'asc' } } },
  stores: {
    include: {
      store: { select: { id: true, name: true, code: true, city: true } },
      request: { select: { id: true, requestNumber: true, status: true } },
      items: { include: { product: { select: { id: true, name: true, sku: true, unit: true } } }, orderBy: { product: { name: 'asc' } } },
    },
    orderBy: { store: { name: 'asc' } },
  },
} satisfies Prisma.PackingOrderInclude;

type Detail = Prisma.PackingOrderGetPayload<{ include: typeof detailInclude }>;

const isAdmin = (c: RequestContext) => c.user.role === Role.ADMIN;

function visibleStores(context: RequestContext, order: Detail) {
  return isAdmin(context) ? order.stores : order.stores.filter((s) => canAccessStore(context.scope, s.storeId));
}

async function present(context: RequestContext, order: Detail) {
  const stores = visibleStores(context, order);
  const productIds = order.items.map((i) => i.productId);
  const available = new Map<string, number>();
  if (context.user.role !== Role.STORE) {
    const stock = await prisma.warehouseStock.findMany({ where: { warehouseId: order.warehouseId, productId: { in: productIds } } });
    stock.forEach((s) => available.set(s.productId, s.quantity - s.reservedQuantity));
  }
  const lines = stores.flatMap((s) => s.items);

  const items = order.items.map((item) => {
    const allocs = lines.filter((l) => l.productId === item.productId);
    const sum = (k: 'requestedQuantity' | 'approvedQuantity' | 'allocatedQuantity' | 'packedQuantity' | 'dispatchedQuantity' | 'receivedQuantity' | 'damagedQuantity') =>
      allocs.reduce((a, l) => a + l[k], 0);
    const allocated = sum('allocatedQuantity');
    return {
      ...item,
      requestedQuantity: sum('requestedQuantity'),
      approvedQuantity: sum('approvedQuantity'),
      allocatedQuantity: allocated,
      packedQuantity: sum('packedQuantity'),
      dispatchedQuantity: sum('dispatchedQuantity'),
      receivedQuantity: sum('receivedQuantity'),
      damagedQuantity: sum('damagedQuantity'),
      pendingQuantity: Math.max(allocated - sum('receivedQuantity') - sum('damagedQuantity'), 0),
      unallocatedQuantity: Math.max(item.quantity - allocated, 0),
      // While the order holds a reservation its own allocation is already excluded from availability.
      warehouseAvailable: context.user.role === Role.STORE ? undefined : available.get(item.productId) ?? 0,
    };
  });

  return {
    ...order,
    // Store users only see their own store section and their own products.
    items: context.user.role === Role.STORE ? items.filter((i) => i.allocatedQuantity > 0) : items,
    stores: stores.map((s) => ({
      ...s,
      items: s.items.map((l) => ({
        ...l,
        pendingQuantity: Math.max(l.allocatedQuantity - l.receivedQuantity - l.damagedQuantity, 0),
        shortQuantity: s.status === PackingStoreStatus.RECEIVED ? Math.max(l.dispatchedQuantity - l.receivedQuantity - l.damagedQuantity, 0) : 0,
      })),
    })),
  };
}

async function loadRaw(db: Tx | typeof prisma, id: string) {
  const order = await db.packingOrder.findUnique({ where: { id }, include: detailInclude });
  if (!order) throw ApiError.notFound('Packing order');
  return order;
}

async function loadInScope(context: RequestContext, id: string, db: Tx | typeof prisma = prisma) {
  const order = await loadRaw(db, id);
  if (!isAdmin(context) && !order.stores.some((s) => canAccessStore(context.scope, s.storeId))) {
    throw ApiError.notFound('Packing order');
  }
  // Stores only see orders once they have been assigned to them.
  if (context.user.role === Role.STORE && order.status === S.DRAFT) throw ApiError.notFound('Packing order');
  return order;
}

export async function getPackingOrder(context: RequestContext, id: string) {
  return present(context, await loadInScope(context, id));
}

export async function listPackingOrders(context: RequestContext, q: ListQuery) {
  const search = contains(q.search);
  const storeCondition: Prisma.PackingOrderStoreWhereInput | undefined = q.storeId
    ? (assertStoreAccess(context.scope, q.storeId), { storeId: q.storeId })
    : context.scope.all
      ? undefined
      : { storeId: { in: context.scope.storeIds } };

  const where: Prisma.PackingOrderWhereInput = {
    ...(storeCondition ? { stores: { some: storeCondition } } : {}),
    ...(q.status ? { status: { in: q.status.split(',') as S[] } } : {}),
    ...(context.user.role === Role.STORE ? { status: q.status ? { in: (q.status.split(',') as S[]).filter((s) => s !== S.DRAFT) } : { not: S.DRAFT } } : {}),
    ...(dateRange(q) ? { createdAt: dateRange(q) } : {}),
    ...(q.productId ? { items: { some: { productId: q.productId } } } : {}),
    ...(search ? { OR: [{ orderNumber: search }, { notes: search }, { stores: { some: { store: { name: search } } } }] } : {}),
  };

  const [rows, total] = await Promise.all([
    prisma.packingOrder.findMany({
      where,
      include: {
        warehouse: { select: { id: true, name: true, code: true } },
        stores: {
          where: storeCondition,
          select: {
            id: true,
            status: true,
            store: { select: { id: true, name: true, code: true } },
            items: { select: { allocatedQuantity: true, packedQuantity: true, dispatchedQuantity: true, receivedQuantity: true } },
          },
        },
        _count: { select: { items: true } },
      },
      orderBy: orderBy(q, {
        orderNumber: (d) => ({ orderNumber: d }),
        status: (d) => ({ status: d }),
        createdAt: (d) => ({ createdAt: d }),
        dispatchedAt: (d) => ({ dispatchedAt: { sort: d, nulls: 'last' } }),
      }, { createdAt: 'desc' }),
      ...pageArgs(q),
    }),
    prisma.packingOrder.count({ where }),
  ]);

  return {
    rows: rows.map(({ stores, ...o }) => {
      const lines = stores.flatMap((s) => s.items);
      return {
        ...o,
        itemCount: o._count.items,
        storeCount: stores.length,
        stores: stores.map((s) => ({ id: s.id, status: s.status, store: s.store })),
        totalAllocated: lines.reduce((a, l) => a + l.allocatedQuantity, 0),
        totalPacked: lines.reduce((a, l) => a + l.packedQuantity, 0),
        totalDispatched: lines.reduce((a, l) => a + l.dispatchedQuantity, 0),
        totalReceived: lines.reduce((a, l) => a + l.receivedQuantity, 0),
      };
    }),
    total,
  };
}

// ─────────────────────────── Draft editing ───────────────────────────

interface AllocationLine {
  productId: string;
  allocatedQuantity: number;
  requestedQuantity?: number;
  approvedQuantity?: number;
  requestItemId?: string | null;
}
interface StorePlan {
  storeId: string;
  requestId?: string | null;
  items: AllocationLine[];
}

/** Validates products, stores and quantities. Allocated per product ≤ planned ≤ warehouse available. */
async function validatePlan(tx: Tx, warehouseId: string, items: { productId: string; quantity: number }[], stores: StorePlan[]) {
  const productIds = items.map((i) => i.productId);
  const products = await tx.product.findMany({ where: { id: { in: productIds } }, select: { id: true, name: true, status: true } });
  if (products.length !== productIds.length) throw ApiError.validation([{ field: 'items', message: 'One or more products do not exist' }]);
  const inactive = products.find((p) => p.status !== RecordStatus.ACTIVE);
  if (inactive) throw ApiError.validation([{ field: 'items', message: `${inactive.name} is inactive` }]);
  const name = (id: string) => products.find((p) => p.id === id)?.name ?? 'product';

  let foundStores: { id: string; name: string; status: RecordStatus }[] = [];
  if (stores.length) {
    foundStores = await tx.store.findMany({ where: { id: { in: stores.map((s) => s.storeId) } }, select: { id: true, name: true, status: true } });
    if (foundStores.length !== stores.length) throw ApiError.validation([{ field: 'stores', message: 'One or more stores do not exist' }]);
    const inactiveStore = foundStores.find((s) => s.status !== RecordStatus.ACTIVE);
    if (inactiveStore) throw ApiError.validation([{ field: 'stores', message: `${inactiveStore.name} is inactive` }]);
  }
  const storeName = (storeId: string) => foundStores.find((s) => s.id === storeId)?.name ?? 'This store';

  const errors: { field: string; message: string }[] = [];
  const stock = await tx.warehouseStock.findMany({ where: { warehouseId, productId: { in: productIds } } });
  items.forEach((item, index) => {
    const allocated = stores.reduce((a, s) => a + (s.items.find((l) => l.productId === item.productId)?.allocatedQuantity ?? 0), 0);
    const row = stock.find((s) => s.productId === item.productId);
    const available = row ? row.quantity - row.reservedQuantity : 0;
    if (allocated > item.quantity) {
      errors.push({ field: `items.${index}.quantity`, message: `${name(item.productId)}: allocated ${allocated} exceeds planned quantity ${item.quantity}` });
    }
    if (allocated > available) {
      errors.push({ field: `items.${index}.quantity`, message: `${name(item.productId)}: allocated ${allocated} exceeds available warehouse stock ${available}` });
    }
  });
  stores.forEach((s, si) => {
    s.items.forEach((l, li) => {
      if (!productIds.includes(l.productId)) {
        errors.push({ field: `stores.${si}.items.${li}.productId`, message: 'Allocated product is not part of this packing order' });
      }
    });
    // A store added to the order with nothing allocated to it is almost
    // always a mistake (or a forgotten cleanup) - block it early rather than
    // silently creating an empty section.
    if (s.items.every((l) => l.allocatedQuantity === 0)) {
      errors.push({ field: `stores.${si}`, message: `${storeName(s.storeId)} has no allocated quantity - remove it or allocate something to it` });
    }
  });
  if (errors.length) throw ApiError.validation(errors);
}

async function writePlan(tx: Tx, orderId: string, items: { productId: string; quantity: number }[], stores: StorePlan[]) {
  await tx.packingOrderStore.deleteMany({ where: { packingOrderId: orderId } });
  await tx.packingOrderItem.deleteMany({ where: { packingOrderId: orderId } });
  await tx.packingOrderItem.createMany({ data: items.map((i) => ({ packingOrderId: orderId, productId: i.productId, quantity: i.quantity })) });
  for (const s of stores) {
    await tx.packingOrderStore.create({
      data: {
        packingOrderId: orderId,
        storeId: s.storeId,
        requestId: s.requestId ?? null,
        items: {
          create: s.items
            .filter((l) => l.allocatedQuantity > 0 || l.requestItemId)
            .map((l) => ({
              productId: l.productId,
              allocatedQuantity: l.allocatedQuantity,
              requestedQuantity: l.requestedQuantity ?? 0,
              approvedQuantity: l.approvedQuantity ?? l.allocatedQuantity,
              requestItemId: l.requestItemId ?? null,
            })),
        },
      },
    });
  }
}

export async function createPackingOrder(context: RequestContext, input: CreateInput) {
  const id = await transaction(async (tx) => {
    const warehouse = await resolveWarehouse(tx, input.warehouseId);
    await validatePlan(tx, warehouse.id, input.items, input.stores);
    const order = await tx.packingOrder.create({
      data: { orderNumber: await nextDocumentNumber(tx, 'PO'), warehouseId: warehouse.id, notes: input.notes, createdById: context.user.id },
    });
    await writePlan(tx, order.id, input.items, input.stores);
    await audit(tx, context, {
      action: 'CREATE',
      module: 'packing_orders',
      recordId: order.id,
      summary: `Created packing order ${order.orderNumber} for ${input.stores.length} store(s)`,
      newValue: input,
    });
    return order.id;
  });
  return getPackingOrder(context, id);
}

/** Builds a draft packing order from one or more approved product requests (one store section per request). */
export async function createFromRequests(context: RequestContext, input: z.infer<typeof packingFromRequestsSchema>) {
  const id = await transaction(async (tx) => {
    const warehouse = await resolveWarehouse(tx, input.warehouseId);
    const requests = await tx.productRequest.findMany({
      where: { id: { in: input.requestIds } },
      include: { items: true, packingOrders: { select: { status: true } } },
    });
    if (requests.length !== input.requestIds.length) throw ApiError.validation([{ field: 'requestIds', message: 'One or more requests do not exist' }]);
    for (const r of requests) {
      if (!PACKABLE.includes(r.status)) throw ApiError.invalidState(`Request ${r.requestNumber} is not approved`);
      if (r.packingOrders.some((p) => p.status !== PackingStoreStatus.CANCELLED)) {
        throw ApiError.invalidState(`Request ${r.requestNumber} already has a packing order`);
      }
    }
    const storeIds = requests.map((r) => r.storeId);
    if (new Set(storeIds).size !== storeIds.length) {
      throw ApiError.badRequest('Select at most one request per store for a single packing order');
    }

    const totals = new Map<string, number>();
    const stores: StorePlan[] = requests.map((r) => ({
      storeId: r.storeId,
      requestId: r.id,
      items: r.items
        .filter((i) => (i.approvedQuantity ?? 0) > 0)
        .map((i) => {
          totals.set(i.productId, (totals.get(i.productId) ?? 0) + i.approvedQuantity!);
          return {
            productId: i.productId,
            requestedQuantity: i.requestedQuantity,
            approvedQuantity: i.approvedQuantity!,
            allocatedQuantity: i.approvedQuantity!,
            requestItemId: i.id,
          };
        }),
    }));
    const items = [...totals.entries()].map(([productId, quantity]) => ({ productId, quantity }));

    // Draft is created even if stock is short so the admin can re-allocate;
    // availability is enforced when the order is assigned.
    const order = await tx.packingOrder.create({
      data: {
        orderNumber: await nextDocumentNumber(tx, 'PO'),
        warehouseId: warehouse.id,
        notes: input.notes ?? `Generated from ${requests.map((r) => r.requestNumber).join(', ')}`,
        createdById: context.user.id,
      },
    });
    await writePlan(tx, order.id, items, stores);
    await audit(tx, context, {
      action: 'CREATE_FROM_REQUESTS',
      module: 'packing_orders',
      recordId: order.id,
      summary: `Generated packing order ${order.orderNumber} from ${requests.map((r) => r.requestNumber).join(', ')}`,
      newValue: { requestIds: input.requestIds },
    });
    return order.id;
  });
  return getPackingOrder(context, id);
}

export async function updatePackingOrder(context: RequestContext, id: string, input: z.infer<typeof updatePackingOrderSchema>) {
  await transaction(async (tx) => {
    const order = await loadRaw(tx, id);
    if (order.status !== S.DRAFT) throw ApiError.invalidState('Only draft packing orders can be edited');
    const warehouseId = input.warehouseId ? (await resolveWarehouse(tx, input.warehouseId)).id : order.warehouseId;
    const items = input.items ?? order.items.map((i) => ({ productId: i.productId, quantity: i.quantity }));

    // Keep request linkage (requested/approved figures) for stores that stay on the order.
    const stores: StorePlan[] = input.stores
      ? input.stores.map((s) => {
          const prev = order.stores.find((p) => p.storeId === s.storeId);
          return {
            storeId: s.storeId,
            requestId: prev?.requestId,
            items: s.items.map((l) => {
              const prevLine = prev?.items.find((x) => x.productId === l.productId);
              return {
                ...l,
                requestedQuantity: prevLine?.requestedQuantity,
                approvedQuantity: prevLine?.approvedQuantity,
                requestItemId: prevLine?.requestItemId,
              };
            }),
          };
        })
      : order.stores.map((s) => ({ storeId: s.storeId, requestId: s.requestId, items: s.items }));

    await validatePlan(tx, warehouseId, items, stores);
    await tx.packingOrder.update({ where: { id }, data: { warehouseId, notes: input.notes ?? order.notes } });
    await writePlan(tx, id, items, stores);
    await audit(tx, context, {
      action: 'UPDATE',
      module: 'packing_orders',
      recordId: id,
      summary: `Updated draft packing order ${order.orderNumber}`,
      oldValue: { items: order.items.map((i) => ({ productId: i.productId, quantity: i.quantity })) },
      newValue: { items, stores: stores.map((s) => ({ storeId: s.storeId, items: s.items.map((l) => ({ productId: l.productId, allocatedQuantity: l.allocatedQuantity })) })) },
    });
  });
  return getPackingOrder(context, id);
}

// ─────────────────────────── Workflow ───────────────────────────

async function transition(tx: Tx, id: string, from: S[], data: Prisma.PackingOrderUpdateManyMutationInput) {
  const result = await tx.packingOrder.updateMany({ where: { id, status: { in: from } }, data });
  if (!result.count) throw ApiError.invalidState('This packing order is no longer in a state that allows this action');
}

const allocatedByProduct = (order: Detail) => {
  const map = new Map<string, number>();
  order.stores.forEach((s) => s.items.forEach((l) => map.set(l.productId, (map.get(l.productId) ?? 0) + l.allocatedQuantity)));
  return map;
};

/** Freezes allocations and reserves warehouse stock. */
export async function assignPackingOrder(context: RequestContext, id: string) {
  await transaction(async (tx) => {
    const order = await loadRaw(tx, id);
    const allocated = allocatedByProduct(order);
    const total = [...allocated.values()].reduce((a, b) => a + b, 0);
    if (!order.stores.length || total === 0) throw ApiError.invalidState('Allocate products to at least one store before assigning');
    await validatePlan(tx, order.warehouseId, order.items, order.stores);

    // Every planned unit must be distributed to a store before the order can
    // be assigned - an unallocated remainder almost always means the admin
    // forgot to finish spreading it across stores.
    const shortfalls = order.items
      .filter((item) => (allocated.get(item.productId) ?? 0) !== item.quantity)
      .map((item) => `${item.product.name} (${allocated.get(item.productId) ?? 0} of ${item.quantity} allocated)`);
    if (shortfalls.length) {
      throw ApiError.validation(shortfalls.map((message) => ({ field: 'items', message: `${message} - fully allocate before assigning` })));
    }
    // (A store with zero allocation is already rejected by validatePlan above.)

    await transition(tx, id, [S.DRAFT], { status: S.ASSIGNED, assignedAt: new Date() });

    for (const [productId, qty] of allocated) {
      await reserve(tx, { kind: 'WAREHOUSE', warehouseId: order.warehouseId }, productId, qty);
    }
    await audit(tx, context, {
      action: 'ASSIGN',
      module: 'packing_orders',
      recordId: id,
      summary: `Assigned packing order ${order.orderNumber} to ${order.stores.map((s) => s.store.name).join(', ')}`,
      newValue: Object.fromEntries(allocated),
    });
    await notify(tx, {
      type: NotificationType.PACKING_CREATED,
      title: 'Packing order created',
      message: `Packing order ${order.orderNumber} has been assigned to your store.`,
      entityType: 'PACKING_ORDER',
      entityId: id,
      storeIds: order.stores.map((s) => s.storeId),
      excludeUserId: context.user.id,
    });
  });
  return getPackingOrder(context, id);
}

export async function startPacking(context: RequestContext, id: string) {
  await transaction(async (tx) => {
    const order = await loadRaw(tx, id);
    await transition(tx, id, [S.ASSIGNED], { status: S.PACKING });
    await audit(tx, context, { action: 'START_PACKING', module: 'packing_orders', recordId: id, summary: `Started packing ${order.orderNumber}` });
  });
  return getPackingOrder(context, id);
}

/**
 * Records packed quantities (default: everything allocated). Packed goods leave
 * the warehouse here: one PACKING movement per product, releasing the reservation.
 */
export async function markPacked(context: RequestContext, id: string, input: z.infer<typeof packSchema>) {
  await transaction(async (tx) => {
    const order = await loadRaw(tx, id);
    if (order.status !== S.ASSIGNED && order.status !== S.PACKING) throw ApiError.invalidState('Only assigned packing orders can be packed');

    const lines = order.stores.flatMap((s) => s.items.map((l) => ({ ...l, storeName: s.store.name })));
    const packed = new Map(input.lines?.map((l) => [l.allocationId, l.packedQuantity]) ?? []);
    if (input.lines?.some((l) => !lines.find((x) => x.id === l.allocationId))) {
      throw ApiError.validation([{ field: 'lines', message: 'Line does not belong to this packing order' }]);
    }
    const errors: { field: string; message: string }[] = [];
    for (const line of lines) {
      const qty = packed.get(line.id) ?? line.allocatedQuantity;
      if (qty > line.allocatedQuantity) {
        errors.push({ field: `lines.${line.id}`, message: `${line.product.name} for ${line.storeName}: packed ${qty} exceeds allocated ${line.allocatedQuantity}` });
      }
    }
    if (errors.length) throw ApiError.validation(errors);

    await transition(tx, id, [S.ASSIGNED, S.PACKING], { status: S.PACKED, packedAt: new Date() });

    const perProduct = new Map<string, { packed: number; allocated: number }>();
    for (const line of lines) {
      const qty = packed.get(line.id) ?? line.allocatedQuantity;
      await tx.packingOrderStoreItem.update({ where: { id: line.id }, data: { packedQuantity: qty } });
      const agg = perProduct.get(line.productId) ?? { packed: 0, allocated: 0 };
      agg.packed += qty;
      agg.allocated += line.allocatedQuantity;
      perProduct.set(line.productId, agg);
    }
    const loc = { kind: 'WAREHOUSE' as const, warehouseId: order.warehouseId };
    for (const [productId, { packed: qty, allocated }] of perProduct) {
      if (qty > 0) {
        await applyMovement(tx, {
          location: loc,
          productId,
          type: MovementType.PACKING,
          quantity: -qty,
          releaseReserved: qty,
          referenceType: ReferenceType.PACKING_ORDER,
          referenceId: id,
          reason: `Packed for ${order.orderNumber}`,
          userId: context.user.id,
        });
      }
      // Anything allocated but not packed goes back to available.
      if (allocated - qty > 0) await releaseReservation(tx, loc, productId, allocated - qty);
    }
    await syncRequestStatus(tx, order.stores.map((s) => s.requestId), ProductRequestStatus.PACKED);
    await audit(tx, context, {
      action: 'PACK',
      module: 'packing_orders',
      recordId: id,
      summary: `Packed ${order.orderNumber}`,
      newValue: Object.fromEntries([...perProduct].map(([k, v]) => [k, v.packed])),
    });
  });
  return getPackingOrder(context, id);
}

export async function dispatchPackingOrder(context: RequestContext, id: string) {
  await transaction(async (tx) => {
    const order = await loadRaw(tx, id);
    await transition(tx, id, [S.PACKED], { status: S.DISPATCHED, dispatchedAt: new Date() });
    const now = new Date();
    for (const s of order.stores) {
      const packedTotal = s.items.reduce((a, l) => a + l.packedQuantity, 0);
      for (const l of s.items) {
        await tx.packingOrderStoreItem.update({ where: { id: l.id }, data: { dispatchedQuantity: l.packedQuantity } });
      }
      await tx.packingOrderStore.update({
        where: { id: s.id },
        data: packedTotal > 0 ? { status: PackingStoreStatus.DISPATCHED, dispatchedAt: now } : { status: PackingStoreStatus.CANCELLED },
      });
    }
    const shipped = (s: Detail['stores'][number]) => s.items.some((l) => l.packedQuantity > 0);
    await syncRequestStatus(tx, order.stores.filter(shipped).map((s) => s.requestId), ProductRequestStatus.DISPATCHED);
    // Sections with nothing packed are cancelled; their requests can be packed again later.
    await revertRequestsToApproved(tx, order.stores.filter((s) => !shipped(s)).map((s) => s.requestId));
    await audit(tx, context, { action: 'DISPATCH', module: 'packing_orders', recordId: id, summary: `Dispatched packing order ${order.orderNumber}` });
    await notify(tx, {
      type: NotificationType.PACKING_DISPATCHED,
      title: 'Packing order dispatched',
      message: `Packing order ${order.orderNumber} is on its way. Please receive it on arrival.`,
      entityType: 'PACKING_ORDER',
      entityId: id,
      storeIds: order.stores.filter((s) => s.items.some((l) => l.packedQuantity > 0)).map((s) => s.storeId),
      excludeUserId: context.user.id,
    });
    // All sections cancelled (nothing packed at all) - close the order.
    if (order.stores.every((s) => s.items.every((l) => l.packedQuantity === 0))) {
      await tx.packingOrder.update({ where: { id }, data: { status: S.COMPLETED, completedAt: now } });
    }
  });
  return getPackingOrder(context, id);
}

/**
 * A store receives its section. Default: everything dispatched arrived in good
 * condition. Good units go to available stock, damaged units to the damaged
 * bucket; missing units are recorded as a shortage (discrepancy).
 */
export async function receivePackingOrder(context: RequestContext, id: string, input: z.infer<typeof receiveLinesSchema>) {
  await transaction(async (tx) => {
    const order = await loadInScope(context, id, tx);
    if (order.status !== S.DISPATCHED) throw ApiError.invalidState('Only dispatched packing orders can be received');

    const storeId = context.user.role === Role.STORE ? context.user.storeId! : input.storeId;
    if (!storeId) throw ApiError.validation([{ field: 'storeId', message: 'Select the receiving store' }]);
    assertStoreAccess(context.scope, storeId);
    const section = order.stores.find((s) => s.storeId === storeId);
    if (!section) throw ApiError.notFound('Packing order');

    const claimed = await tx.packingOrderStore.updateMany({
      where: { id: section.id, status: PackingStoreStatus.DISPATCHED },
      data: { status: PackingStoreStatus.RECEIVED, receivedAt: new Date(), receivedById: context.user.id, receiptNotes: input.notes },
    });
    if (!claimed.count) throw ApiError.invalidState('This shipment was already received');

    const byLine = new Map(input.lines?.map((l) => [l.id, l]) ?? []);
    if (input.lines?.some((l) => !section.items.find((x) => x.id === l.id))) {
      throw ApiError.validation([{ field: 'lines', message: 'Line does not belong to this shipment' }]);
    }
    let discrepancy = false;
    const loc = { kind: 'STORE' as const, storeId };
    for (const line of section.items) {
      const entry = byLine.get(line.id);
      const received = entry?.receivedQuantity ?? line.dispatchedQuantity;
      const damaged = entry?.damagedQuantity ?? 0;
      if (received + damaged > line.dispatchedQuantity) {
        throw ApiError.validation([{ field: `lines.${line.id}`, message: `${line.product.name}: received + damaged exceeds dispatched (${line.dispatchedQuantity})` }]);
      }
      if (received + damaged !== line.dispatchedQuantity || damaged > 0) discrepancy = true;
      await tx.packingOrderStoreItem.update({ where: { id: line.id }, data: { receivedQuantity: received, damagedQuantity: damaged } });
      const common = { location: loc, productId: line.productId, type: MovementType.TRANSFER_IN, referenceType: ReferenceType.PACKING_ORDER, referenceId: id, userId: context.user.id };
      if (received > 0) await applyMovement(tx, { ...common, quantity: received, reason: `Received ${order.orderNumber}` });
      if (damaged > 0) await applyMovement(tx, { ...common, bucket: StockBucket.DAMAGED, quantity: damaged, reason: `Received damaged in ${order.orderNumber}` });
    }

    if (section.requestId) {
      await syncRequestStatus(tx, [section.requestId], discrepancy ? ProductRequestStatus.RECEIVED : ProductRequestStatus.COMPLETED);
    }

    // Close the order once every section is settled.
    const sections = await tx.packingOrderStore.findMany({ where: { packingOrderId: id }, include: { items: true } });
    const settled = sections.every((s) => s.status === PackingStoreStatus.RECEIVED || s.status === PackingStoreStatus.CANCELLED);
    if (settled) {
      const anyDiscrepancy = sections.some((s) =>
        s.items.some((l) => l.damagedQuantity > 0 || l.receivedQuantity + l.damagedQuantity !== l.dispatchedQuantity),
      );
      await tx.packingOrder.update({
        where: { id },
        data: anyDiscrepancy ? { status: S.RECEIVED } : { status: S.COMPLETED, completedAt: new Date() },
      });
    }

    await audit(tx, context, {
      action: 'RECEIVE',
      module: 'packing_orders',
      recordId: id,
      summary: `${section.store.name} received packing order ${order.orderNumber}${discrepancy ? ' with discrepancies' : ''}`,
      newValue: section.items.map((l) => ({ productId: l.productId, dispatched: l.dispatchedQuantity, ...byLine.get(l.id) })),
    });
    await notify(tx, {
      type: NotificationType.STOCK_RECEIVED,
      title: 'Stock received',
      message: `${section.store.name} received packing order ${order.orderNumber}${discrepancy ? ' with discrepancies' : ''}.`,
      entityType: 'PACKING_ORDER',
      entityId: id,
      admins: true,
      storeIds: [storeId],
      managersOnly: true,
      excludeUserId: context.user.id,
    });
  });
  return getPackingOrder(context, id);
}

/** Admin acknowledges receipt discrepancies and closes the order. */
export async function completePackingOrder(context: RequestContext, id: string) {
  await transaction(async (tx) => {
    const order = await loadRaw(tx, id);
    await transition(tx, id, [S.RECEIVED], { status: S.COMPLETED, completedAt: new Date() });
    await syncRequestStatus(tx, order.stores.map((s) => s.requestId), ProductRequestStatus.COMPLETED);
    await audit(tx, context, { action: 'COMPLETE', module: 'packing_orders', recordId: id, summary: `Closed packing order ${order.orderNumber}` });
  });
  return getPackingOrder(context, id);
}

export async function cancelPackingOrder(context: RequestContext, id: string, reason: string) {
  await transaction(async (tx) => {
    const order = await loadRaw(tx, id);
    const from = order.status;
    const cancellable: S[] = [S.DRAFT, S.ASSIGNED, S.PACKING, S.PACKED];
    if (!cancellable.includes(from)) throw ApiError.invalidState('Dispatched packing orders cannot be cancelled');
    // Transition from the exact status read so the stock reversal below matches reality.
    await transition(tx, id, [from], {
      status: S.CANCELLED,
      cancelledAt: new Date(),
      notes: `${order.notes ? `${order.notes}\n` : ''}Cancelled: ${reason}`,
    });
    const loc = { kind: 'WAREHOUSE' as const, warehouseId: order.warehouseId };
    if (from === S.ASSIGNED || from === S.PACKING) {
      for (const [productId, qty] of allocatedByProduct(order)) await releaseReservation(tx, loc, productId, qty);
    }
    if (from === S.PACKED) {
      const packed = new Map<string, number>();
      order.stores.forEach((s) => s.items.forEach((l) => packed.set(l.productId, (packed.get(l.productId) ?? 0) + l.packedQuantity)));
      for (const [productId, qty] of packed) {
        if (qty > 0) {
          await applyMovement(tx, {
            location: loc,
            productId,
            type: MovementType.CANCELLATION,
            quantity: qty,
            referenceType: ReferenceType.PACKING_ORDER,
            referenceId: id,
            reason: `Cancelled ${order.orderNumber}: ${reason}`,
            userId: context.user.id,
          });
        }
      }
    }
    await tx.packingOrderStore.updateMany({ where: { packingOrderId: id }, data: { status: PackingStoreStatus.CANCELLED } });
    await revertRequestsToApproved(tx, order.stores.map((s) => s.requestId));
    await audit(tx, context, { action: 'CANCEL', module: 'packing_orders', recordId: id, summary: `Cancelled packing order ${order.orderNumber} (was ${from}): ${reason}` });
  });
  return getPackingOrder(context, id);
}
