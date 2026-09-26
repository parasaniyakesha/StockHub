import { beforeAll, describe, expect, it } from 'vitest';
import { api, bearer, buildFixture, Fixture, storeOpening } from './helpers';

let f: Fixture;
beforeAll(async () => {
  f = await buildFixture();
  await storeOpening(f, f.storeA.id, { [f.p1.id]: 50 });
  await storeOpening(f, f.storeB.id, { [f.p1.id]: 30 });
  await storeOpening(f, f.storeC.id, { [f.p1.id]: 20 });
  // One sale per store.
  for (const t of [f.tokens.a, f.tokens.b, f.tokens.c]) {
    const res = await api().post('/api/sales').set(bearer(t)).send({ paymentMethod: 'CASH', items: [{ productId: f.p1.id, quantity: 1 }] });
    expect(res.status).toBe(201);
  }
});

describe('store users are confined to their own store', () => {
  it('cannot query another store stock', async () => {
    const res = await api().get(`/api/stock?storeId=${f.storeB.id}`).set(bearer(f.tokens.a));
    expect(res.status).toBe(403);
    expect(res.body.code).toBe('FORBIDDEN');
  });

  it('only sees own store rows when no filter is given', async () => {
    const res = await api().get('/api/stock').set(bearer(f.tokens.a));
    expect(res.status).toBe(200);
    expect(new Set(res.body.data.map((r: { storeId: string }) => r.storeId))).toEqual(new Set([f.storeA.id]));
  });

  it('cannot read another store sale by id (reported as not found)', async () => {
    const saleB = (await api().get('/api/sales').set(bearer(f.tokens.b))).body.data[0];
    const res = await api().get(`/api/sales/${saleB.id}`).set(bearer(f.tokens.a));
    expect(res.status).toBe(404);
  });

  it('cannot record a sale for another store (storeId in body is ignored/forced)', async () => {
    const res = await api().post('/api/sales').set(bearer(f.tokens.a)).send({ storeId: f.storeB.id, paymentMethod: 'CASH', items: [{ productId: f.p1.id, quantity: 1 }] });
    expect(res.status).toBe(201);
    expect(res.body.data.storeId).toBe(f.storeA.id);
  });

  it('cannot see the central warehouse or other stores in the store list', async () => {
    expect((await api().get('/api/stock?locationType=WAREHOUSE').set(bearer(f.tokens.a))).status).toBe(403);
    const stores = await api().get('/api/stores').set(bearer(f.tokens.a));
    expect(stores.body.data.map((s: { id: string }) => s.id)).toEqual([f.storeA.id]);
    expect((await api().get(`/api/stores/${f.storeB.id}`).set(bearer(f.tokens.a))).status).toBe(404);
  });

  it('does not receive cost prices', async () => {
    const res = await api().get('/api/products').set(bearer(f.tokens.a));
    expect(res.status).toBe(200);
    expect(res.body.data[0].purchasePrice).toBeUndefined();
    expect(res.body.data[0].warehouseQuantity).toBeUndefined();
    const detail = await api().get(`/api/products/${f.p1.id}`).set(bearer(f.tokens.a));
    expect(detail.body.data.purchasePrice).toBeUndefined();
  });

  it('cannot perform admin actions', async () => {
    expect((await api().post('/api/products').set(bearer(f.tokens.a)).send({})).status).toBe(403);
    expect((await api().post('/api/stores').set(bearer(f.tokens.a)).send({})).status).toBe(403);
    expect((await api().get('/api/users').set(bearer(f.tokens.a))).status).toBe(403);
    expect((await api().get('/api/audit-logs').set(bearer(f.tokens.a))).status).toBe(403);
    expect((await api().post('/api/stock/adjustments').set(bearer(f.tokens.a)).send({})).status).toBe(403);
    expect((await api().put('/api/settings').set(bearer(f.tokens.a)).send({})).status).toBe(403);
  });

  it('reports are scoped to own store and cannot target others', async () => {
    const res = await api().get('/api/reports/sales?groupBy=store').set(bearer(f.tokens.a));
    expect(res.status).toBe(200);
    expect(res.body.data.rows.map((r: { code: string }) => r.code)).toEqual(['STA']);
    expect((await api().get(`/api/reports/sales?groupBy=store&storeId=${f.storeC.id}`).set(bearer(f.tokens.a))).status).toBe(403);
  });
});

describe('managers are confined to assigned stores', () => {
  it('sees only assigned stores', async () => {
    const res = await api().get('/api/stores').set(bearer(f.tokens.m1));
    expect(res.body.data.map((s: { code: string }) => s.code).sort()).toEqual(['STA', 'STB']);
  });

  it('cannot access an unassigned store', async () => {
    expect((await api().get(`/api/stock?storeId=${f.storeC.id}`).set(bearer(f.tokens.m1))).status).toBe(403);
    expect((await api().get(`/api/sales?storeId=${f.storeC.id}`).set(bearer(f.tokens.m1))).status).toBe(403);
    expect((await api().get(`/api/stores/${f.storeC.id}`).set(bearer(f.tokens.m1))).status).toBe(404);
  });

  it('aggregated sales only include assigned stores', async () => {
    const res = await api().get('/api/sales').set(bearer(f.tokens.m1));
    expect(new Set(res.body.data.map((s: { storeId: string }) => s.storeId))).toEqual(new Set([f.storeA.id, f.storeB.id]));
  });

  it('gains access as soon as the admin assigns the store, and loses it when removed', async () => {
    const assign = await api().put(`/api/managers/${f.m1.id}/stores`).set(bearer(f.tokens.admin)).send({ storeIds: [f.storeA.id, f.storeB.id, f.storeC.id] });
    expect(assign.status).toBe(200);
    expect((await api().get(`/api/stock?storeId=${f.storeC.id}`).set(bearer(f.tokens.m1))).status).toBe(200);
    await api().put(`/api/managers/${f.m1.id}/stores`).set(bearer(f.tokens.admin)).send({ storeIds: [f.storeA.id, f.storeB.id] });
    expect((await api().get(`/api/stock?storeId=${f.storeC.id}`).set(bearer(f.tokens.m1))).status).toBe(403);
  });

  it('permissions are configurable per manager', async () => {
    expect((await api().post('/api/stock/adjustments').set(bearer(f.tokens.m1)).send({ locationType: 'STORE', storeId: f.storeA.id, reason: 'Count', items: [{ productId: f.p1.id, quantity: 1 }] })).status).toBe(403);
    await api().put(`/api/managers/${f.m1.id}/permissions`).set(bearer(f.tokens.admin)).send({ permissions: ['stock.view', 'stock.adjust'] });
    const ok = await api().post('/api/stock/adjustments').set(bearer(f.tokens.m1)).send({ locationType: 'STORE', storeId: f.storeA.id, reason: 'Count', items: [{ productId: f.p1.id, quantity: 1 }] });
    expect(ok.status).toBe(201);
    // ...still not for unassigned stores
    const denied = await api().post('/api/stock/adjustments').set(bearer(f.tokens.m1)).send({ locationType: 'STORE', storeId: f.storeC.id, reason: 'Count', items: [{ productId: f.p1.id, quantity: 1 }] });
    expect(denied.status).toBe(403);
    // ...and never for the warehouse
    const wh = await api().post('/api/stock/adjustments').set(bearer(f.tokens.m1)).send({ locationType: 'WAREHOUSE', reason: 'Count', items: [{ productId: f.p1.id, quantity: 1 }] });
    expect(wh.status).toBe(403);
  });

  it('cannot manage products, managers or audit', async () => {
    expect((await api().post('/api/products').set(bearer(f.tokens.m1)).send({})).status).toBe(403);
    expect((await api().get('/api/managers').set(bearer(f.tokens.m1))).status).toBe(403);
    expect((await api().get('/api/audit-logs').set(bearer(f.tokens.m1))).status).toBe(403);
  });
});

describe('admin filters are exact', () => {
  it('storeId filter returns only that store', async () => {
    const res = await api().get(`/api/sales?storeId=${f.storeB.id}`).set(bearer(f.tokens.admin));
    expect(res.status).toBe(200);
    expect(res.body.data.length).toBeGreaterThan(0);
    expect(res.body.data.every((s: { storeId: string }) => s.storeId === f.storeB.id)).toBe(true);
    const stock = await api().get(`/api/stock?storeId=${f.storeC.id}`).set(bearer(f.tokens.admin));
    expect(stock.body.data.every((s: { storeId: string }) => s.storeId === f.storeC.id)).toBe(true);
  });

  it('sees company-wide data without filters', async () => {
    const res = await api().get('/api/stock?limit=100').set(bearer(f.tokens.admin));
    expect(new Set(res.body.data.map((r: { storeId: string }) => r.storeId)).size).toBe(3);
  });
});
