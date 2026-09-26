import { beforeAll, describe, expect, it } from 'vitest';
import { api, assertLedgerConsistent, bearer, buildFixture, Fixture, stockUp, storeQty, warehouseQty } from './helpers';

let f: Fixture;
beforeAll(async () => {
  f = await buildFixture();
  await stockUp(f, { [f.p1.id]: 100, [f.p2.id]: 40 });
});

describe('product request → packing order → dispatch → receive', () => {
  let requestA: { id: string; items: { id: string; productId: string }[] };
  let requestB: { id: string; items: { id: string; productId: string }[] };
  let orderId: string;

  it('store creates and submits a request', async () => {
    const res = await api().post('/api/product-requests').set(bearer(f.tokens.a)).send({
      submit: true,
      items: [{ productId: f.p1.id, requestedQuantity: 50 }, { productId: f.p2.id, requestedQuantity: 30 }],
    });
    expect(res.status).toBe(201);
    expect(res.body.data.status).toBe('SUBMITTED');
    expect(res.body.data.requestNumber).toMatch(/^REQ-\d+$/);
    requestA = res.body.data;
    const b = await api().post('/api/product-requests').set(bearer(f.tokens.b)).send({ submit: true, items: [{ productId: f.p1.id, requestedQuantity: 40 }] });
    requestB = b.body.data;
  });

  it('store cannot approve; manager of another store cannot see it', async () => {
    expect((await api().put(`/api/product-requests/${requestA.id}/approve`).set(bearer(f.tokens.a)).send({ items: [] })).status).toBe(403);
    expect((await api().get(`/api/product-requests/${requestA.id}`).set(bearer(f.tokens.m2))).status).toBe(404);
    expect((await api().put(`/api/product-requests/${requestA.id}/approve`).set(bearer(f.tokens.m2)).send({ items: requestA.items.map((i) => ({ itemId: i.id, approvedQuantity: 1 })) })).status).toBe(404);
  });

  it('approved quantities cannot exceed requested quantities', async () => {
    const res = await api().put(`/api/product-requests/${requestA.id}/approve`).set(bearer(f.tokens.m1)).send({
      items: requestA.items.map((i) => ({ itemId: i.id, approvedQuantity: 999 })),
    });
    expect(res.status).toBe(422);
  });

  it('manager partially approves', async () => {
    const res = await api().put(`/api/product-requests/${requestA.id}/approve`).set(bearer(f.tokens.m1)).send({
      items: requestA.items.map((i) => ({ itemId: i.id, approvedQuantity: i.productId === f.p1.id ? 40 : 30 })),
    });
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('PARTIALLY_APPROVED');
    const b = await api().put(`/api/product-requests/${requestB.id}/approve`).set(bearer(f.tokens.m1)).send({ items: requestB.items.map((i) => ({ itemId: i.id, approvedQuantity: 40 })) });
    expect(b.body.data.status).toBe('APPROVED');
    // Double approval is rejected.
    expect((await api().put(`/api/product-requests/${requestB.id}/approve`).set(bearer(f.tokens.m1)).send({ items: requestB.items.map((i) => ({ itemId: i.id, approvedQuantity: 40 })) })).status).toBe(409);
  });

  it('generates one multi-store packing order from approved requests', async () => {
    const res = await api().post('/api/packing-orders/from-requests').set(bearer(f.tokens.admin)).send({ requestIds: [requestA.id, requestB.id] });
    expect(res.status).toBe(201);
    orderId = res.body.data.id;
    expect(res.body.data.stores).toHaveLength(2);
    const p1 = res.body.data.items.find((i: { productId: string }) => i.productId === f.p1.id);
    expect(p1).toMatchObject({ quantity: 80, allocatedQuantity: 80, requestedQuantity: 90, approvedQuantity: 80, warehouseAvailable: 100 });
    // A request can only be packed once.
    expect((await api().post('/api/packing-orders/from-requests').set(bearer(f.tokens.admin)).send({ requestIds: [requestA.id] })).status).toBe(409);
  });

  it('draft is invisible to stores; allocation cannot exceed available stock', async () => {
    expect((await api().get(`/api/packing-orders/${orderId}`).set(bearer(f.tokens.a))).status).toBe(404);
    const detail = (await api().get(`/api/packing-orders/${orderId}`).set(bearer(f.tokens.admin))).body.data;
    const res = await api().put(`/api/packing-orders/${orderId}`).set(bearer(f.tokens.admin)).send({
      items: [{ productId: f.p1.id, quantity: 150 }, { productId: f.p2.id, quantity: 30 }],
      stores: detail.stores.map((s: { storeId: string }) => ({
        storeId: s.storeId,
        items: [{ productId: f.p1.id, allocatedQuantity: 75 }, ...(s.storeId === f.storeA.id ? [{ productId: f.p2.id, allocatedQuantity: 30 }] : [])],
      })),
    });
    expect(res.status).toBe(422);
    expect(JSON.stringify(res.body.errors)).toContain('exceeds available warehouse stock 100');
  });

  it('assigning reserves warehouse stock and blocks competing allocations', async () => {
    const res = await api().put(`/api/packing-orders/${orderId}/assign`).set(bearer(f.tokens.admin));
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('ASSIGNED');
    expect(await warehouseQty(f.warehouse.id, f.p1.id)).toMatchObject({ quantity: 100, reservedQuantity: 80 });

    // Only 20 of P1 left to allocate.
    const competing = await api().post('/api/packing-orders').set(bearer(f.tokens.admin)).send({
      items: [{ productId: f.p1.id, quantity: 30 }],
      stores: [{ storeId: f.storeC.id, items: [{ productId: f.p1.id, allocatedQuantity: 30 }] }],
    });
    expect(competing.status).toBe(422);
    // Store now sees its own section only.
    const asStore = await api().get(`/api/packing-orders/${orderId}`).set(bearer(f.tokens.a));
    expect(asStore.status).toBe(200);
    expect(asStore.body.data.stores.map((s: { storeId: string }) => s.storeId)).toEqual([f.storeA.id]);
  });

  it('packing removes stock from the warehouse and releases the reservation', async () => {
    const detail = (await api().get(`/api/packing-orders/${orderId}`).set(bearer(f.tokens.admin))).body.data;
    const lineAp1 = detail.stores.find((s: { storeId: string }) => s.storeId === f.storeA.id).items.find((l: { productId: string }) => l.productId === f.p1.id);
    // Pack more than allocated → rejected
    expect((await api().put(`/api/packing-orders/${orderId}/pack`).set(bearer(f.tokens.admin)).send({ lines: [{ allocationId: lineAp1.id, packedQuantity: 41 }] })).status).toBe(422);
    // Short-pack Store A P1 (38 of 40)
    const res = await api().put(`/api/packing-orders/${orderId}/pack`).set(bearer(f.tokens.admin)).send({ lines: [{ allocationId: lineAp1.id, packedQuantity: 38 }] });
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('PACKED');
    expect(await warehouseQty(f.warehouse.id, f.p1.id)).toMatchObject({ quantity: 22, reservedQuantity: 0 });
  });

  it('dispatch is single-shot (duplicate transitions are rejected)', async () => {
    const [one, two] = await Promise.all([
      api().put(`/api/packing-orders/${orderId}/dispatch`).set(bearer(f.tokens.admin)),
      api().put(`/api/packing-orders/${orderId}/dispatch`).set(bearer(f.tokens.admin)),
    ]);
    expect([one.status, two.status].sort()).toEqual([200, 409]);
  });

  it('stores receive their own section; discrepancies keep the order open', async () => {
    // Store C is not on this order.
    expect((await api().put(`/api/packing-orders/${orderId}/receive`).set(bearer(f.tokens.c)).send({})).status).toBe(404);

    const detail = (await api().get(`/api/packing-orders/${orderId}`).set(bearer(f.tokens.a))).body.data;
    const lines = detail.stores[0].items;
    const p2Line = lines.find((l: { productId: string }) => l.productId === f.p2.id);
    const recvA = await api().put(`/api/packing-orders/${orderId}/receive`).set(bearer(f.tokens.a)).send({
      lines: lines.map((l: { id: string; productId: string; dispatchedQuantity: number }) =>
        l.id === p2Line.id ? { id: l.id, receivedQuantity: 28, damagedQuantity: 2 } : { id: l.id, receivedQuantity: l.dispatchedQuantity }),
    });
    expect(recvA.status).toBe(200);
    expect(await storeQty(f.storeA.id, f.p1.id)).toMatchObject({ quantity: 38 });
    expect(await storeQty(f.storeA.id, f.p2.id)).toMatchObject({ quantity: 28, damagedQuantity: 2 });
    // Receiving twice is rejected.
    expect((await api().put(`/api/packing-orders/${orderId}/receive`).set(bearer(f.tokens.a)).send({})).status).toBe(409);

    const recvB = await api().put(`/api/packing-orders/${orderId}/receive`).set(bearer(f.tokens.b)).send({});
    expect(recvB.body.data.status).toBe('RECEIVED'); // discrepancy at Store A
    const reqA = await api().get(`/api/product-requests/${requestA.id}`).set(bearer(f.tokens.a));
    expect(reqA.body.data.status).toBe('RECEIVED');
    const reqB = await api().get(`/api/product-requests/${requestB.id}`).set(bearer(f.tokens.b));
    expect(reqB.body.data.status).toBe('COMPLETED');

    const done = await api().put(`/api/packing-orders/${orderId}/complete`).set(bearer(f.tokens.admin));
    expect(done.body.data.status).toBe('COMPLETED');
  });

  it('cancelling a packed order returns stock to the warehouse', async () => {
    const po = await api().post('/api/packing-orders').set(bearer(f.tokens.admin)).send({
      items: [{ productId: f.p1.id, quantity: 10 }],
      stores: [{ storeId: f.storeC.id, items: [{ productId: f.p1.id, allocatedQuantity: 10 }] }],
    });
    await api().put(`/api/packing-orders/${po.body.data.id}/assign`).set(bearer(f.tokens.admin));
    await api().put(`/api/packing-orders/${po.body.data.id}/pack`).set(bearer(f.tokens.admin)).send({});
    expect((await warehouseQty(f.warehouse.id, f.p1.id)).quantity).toBe(12);
    const res = await api().put(`/api/packing-orders/${po.body.data.id}/cancel`).set(bearer(f.tokens.admin)).send({ reason: 'Wrong store' });
    expect(res.body.data.status).toBe('CANCELLED');
    expect(await warehouseQty(f.warehouse.id, f.p1.id)).toMatchObject({ quantity: 22, reservedQuantity: 0 });
  });

  it('ledger reconciles', async () => {
    expect(await assertLedgerConsistent()).toBe(0);
  });
});

describe('transfers', () => {
  let transferId: string;

  it('store B requests stock from store A', async () => {
    const res = await api().post('/api/transfers').set(bearer(f.tokens.b)).send({
      sourceType: 'STORE', fromStoreId: f.storeA.id, toStoreId: f.storeB.id, items: [{ productId: f.p1.id, quantity: 10 }],
    });
    expect(res.status).toBe(201);
    expect(res.body.data.status).toBe('REQUESTED');
    transferId = res.body.data.id;
    // Store C cannot create a transfer between A and B.
    expect((await api().post('/api/transfers').set(bearer(f.tokens.c)).send({ sourceType: 'STORE', fromStoreId: f.storeA.id, toStoreId: f.storeB.id, items: [{ productId: f.p1.id, quantity: 1 }] })).status).toBe(403);
  });

  it('only authorised approvers may approve', async () => {
    expect((await api().put(`/api/transfers/${transferId}/approve`).set(bearer(f.tokens.b)).send({})).status).toBe(403);
    expect((await api().put(`/api/transfers/${transferId}/approve`).set(bearer(f.tokens.m2)).send({})).status).toBe(404);
  });

  it('approval reserves source stock; stock moves only on dispatch and receipt', async () => {
    const res = await api().put(`/api/transfers/${transferId}/approve`).set(bearer(f.tokens.m1)).send({});
    expect(res.status).toBe(200);
    expect(await storeQty(f.storeA.id, f.p1.id)).toMatchObject({ quantity: 38, reservedQuantity: 10 });
    expect((await storeQty(f.storeB.id, f.p1.id)).quantity).toBe(40);

    // Reserved stock cannot be sold.
    const sale = await api().post('/api/sales').set(bearer(f.tokens.a)).send({ paymentMethod: 'CASH', items: [{ productId: f.p1.id, quantity: 29 }] });
    expect(sale.status).toBe(409);

    // Destination cannot dispatch.
    expect((await api().put(`/api/transfers/${transferId}/dispatch`).set(bearer(f.tokens.b))).status).toBe(403);
    const dispatched = await api().put(`/api/transfers/${transferId}/dispatch`).set(bearer(f.tokens.a));
    expect(dispatched.body.data.status).toBe('DISPATCHED');
    expect(await storeQty(f.storeA.id, f.p1.id)).toMatchObject({ quantity: 28, reservedQuantity: 0 });

    // Source cannot receive.
    expect((await api().put(`/api/transfers/${transferId}/receive`).set(bearer(f.tokens.a)).send({})).status).toBe(403);
    const received = await api().put(`/api/transfers/${transferId}/receive`).set(bearer(f.tokens.b)).send({});
    expect(received.body.data.status).toBe('COMPLETED');
    expect((await storeQty(f.storeB.id, f.p1.id)).quantity).toBe(50);
  });

  it('cancelling an approved transfer releases the reservation', async () => {
    const t = await api().post('/api/transfers').set(bearer(f.tokens.admin)).send({ sourceType: 'WAREHOUSE', toStoreId: f.storeC.id, items: [{ productId: f.p1.id, quantity: 5 }] });
    await api().put(`/api/transfers/${t.body.data.id}/approve`).set(bearer(f.tokens.admin)).send({});
    expect((await warehouseQty(f.warehouse.id, f.p1.id)).reservedQuantity).toBe(5);
    await api().put(`/api/transfers/${t.body.data.id}/cancel`).set(bearer(f.tokens.admin)).send({});
    expect((await warehouseQty(f.warehouse.id, f.p1.id)).reservedQuantity).toBe(0);
  });

  it('duplicate submissions with the same clientRequestId create one transfer', async () => {
    const body = { sourceType: 'STORE', fromStoreId: f.storeA.id, toStoreId: f.storeB.id, clientRequestId: 'tr-dup-0001', items: [{ productId: f.p1.id, quantity: 1 }] };
    const [x, y] = await Promise.all([api().post('/api/transfers').set(bearer(f.tokens.b)).send(body), api().post('/api/transfers').set(bearer(f.tokens.b)).send(body)]);
    const ids = new Set([x, y].filter((r) => r.status < 300).map((r) => r.body.data.id));
    expect(ids.size).toBe(1);
  });

  it('ledger reconciles', async () => {
    expect(await assertLedgerConsistent()).toBe(0);
  });
});

describe('packing order validation', () => {
  beforeAll(async () => {
    // Top up regardless of what earlier describes in this file consumed, so
    // these tests never fail on insufficient stock rather than the rule under test.
    await api().post('/api/stock/purchases').set(bearer(f.tokens.admin)).send({ items: [{ productId: f.p1.id, quantity: 50 }, { productId: f.p2.id, quantity: 50 }] });
  });

  it('rejects a draft (create or update) that leaves a store with zero allocation', async () => {
    const created = await api().post('/api/packing-orders').set(bearer(f.tokens.admin)).send({
      items: [{ productId: f.p1.id, quantity: 10 }],
      stores: [
        { storeId: f.storeA.id, items: [{ productId: f.p1.id, allocatedQuantity: 10 }] },
        { storeId: f.storeC.id, items: [] }, // added but never given anything
      ],
    });
    expect(created.status).toBe(422);
    expect(JSON.stringify(created.body.errors)).toContain('has no allocated quantity');

    // Same rule applies when updating an existing draft.
    const draft = await api().post('/api/packing-orders').set(bearer(f.tokens.admin)).send({
      items: [{ productId: f.p1.id, quantity: 10 }],
      stores: [{ storeId: f.storeA.id, items: [{ productId: f.p1.id, allocatedQuantity: 10 }] }],
    });
    expect(draft.status).toBe(201);
    const updated = await api().put(`/api/packing-orders/${draft.body.data.id}`).set(bearer(f.tokens.admin)).send({
      items: [{ productId: f.p1.id, quantity: 10 }],
      stores: [
        { storeId: f.storeA.id, items: [{ productId: f.p1.id, allocatedQuantity: 10 }] },
        { storeId: f.storeB.id, items: [{ productId: f.p1.id, allocatedQuantity: 0 }] },
      ],
    });
    expect(updated.status).toBe(422);
  });

  it('rejects creating (or updating to) a packing order with no stores at all', async () => {
    const noStores = await api().post('/api/packing-orders').set(bearer(f.tokens.admin)).send({
      items: [{ productId: f.p1.id, quantity: 10 }],
      stores: [],
    });
    expect(noStores.status).toBe(422);
    expect(JSON.stringify(noStores.body.errors)).toContain('at least one store');

    const draft = await api().post('/api/packing-orders').set(bearer(f.tokens.admin)).send({
      items: [{ productId: f.p1.id, quantity: 10 }],
      stores: [{ storeId: f.storeA.id, items: [{ productId: f.p1.id, allocatedQuantity: 10 }] }],
    });
    expect(draft.status).toBe(201);
    const clearedStores = await api().put(`/api/packing-orders/${draft.body.data.id}`).set(bearer(f.tokens.admin)).send({
      items: [{ productId: f.p1.id, quantity: 10 }],
      stores: [],
    });
    expect(clearedStores.status).toBe(422);
  });

  it('refuses to assign until every planned unit is allocated to a store', async () => {
    const draft = await api().post('/api/packing-orders').set(bearer(f.tokens.admin)).send({
      items: [{ productId: f.p2.id, quantity: 20 }],
      stores: [{ storeId: f.storeA.id, items: [{ productId: f.p2.id, allocatedQuantity: 12 }] }], // 8 short
    });
    expect(draft.status).toBe(201);
    const id = draft.body.data.id;

    const assign = await api().put(`/api/packing-orders/${id}/assign`).set(bearer(f.tokens.admin));
    expect(assign.status).toBe(422);
    expect(JSON.stringify(assign.body.errors)).toContain('12 of 20 allocated');

    // Top up the allocation to fully distribute the planned quantity, then it succeeds.
    await api().put(`/api/packing-orders/${id}`).set(bearer(f.tokens.admin)).send({
      items: [{ productId: f.p2.id, quantity: 20 }],
      stores: [{ storeId: f.storeA.id, items: [{ productId: f.p2.id, allocatedQuantity: 20 }] }],
    });
    const ok = await api().put(`/api/packing-orders/${id}/assign`).set(bearer(f.tokens.admin));
    expect(ok.status).toBe(200);
    expect(ok.body.data.status).toBe('ASSIGNED');
    await api().put(`/api/packing-orders/${id}/cancel`).set(bearer(f.tokens.admin)).send({ reason: 'cleanup' });
  });

  it('ledger reconciles', async () => {
    expect(await assertLedgerConsistent()).toBe(0);
  });
});
