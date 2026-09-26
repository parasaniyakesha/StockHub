import { beforeAll, describe, expect, it } from 'vitest';
import { api, assertLedgerConsistent, bearer, buildFixture, Fixture, stockUp, storeOpening, storeQty, warehouseQty } from './helpers';
import { prisma } from '../src/utils/prisma';

let f: Fixture;
beforeAll(async () => {
  f = await buildFixture();
  await stockUp(f, { [f.p1.id]: 100, [f.p2.id]: 50 });
});

describe('stock ledger', () => {
  it('opening stock can only be recorded once per location', async () => {
    const res = await api().post('/api/stock/opening').set(bearer(f.tokens.admin)).send({ locationType: 'WAREHOUSE', items: [{ productId: f.p1.id, quantity: 5 }] });
    expect(res.status).toBe(409);
    expect(res.body.code).toBe('INVALID_STATE');
  });

  it('purchases add stock with a movement', async () => {
    const res = await api().post('/api/stock/purchases').set(bearer(f.tokens.admin)).send({ supplierReference: 'PO-9', items: [{ productId: f.p1.id, quantity: 200 }] });
    expect(res.status).toBe(201);
    expect((await warehouseQty(f.warehouse.id, f.p1.id)).quantity).toBe(300);
    const m = await prisma.stockMovement.findFirst({ where: { type: 'PURCHASE', productId: f.p1.id } });
    expect(m).toMatchObject({ quantity: 200, balanceAfter: 300, referenceId: 'PO-9' });
  });

  it('adjustments cannot drive stock negative, and a failing line rolls back the whole batch', async () => {
    const before = await prisma.stockMovement.count();
    const res = await api().post('/api/stock/adjustments').set(bearer(f.tokens.admin)).send({
      locationType: 'WAREHOUSE',
      reason: 'Count correction',
      items: [
        { productId: f.p1.id, quantity: -10 },
        { productId: f.p2.id, quantity: -51 },
      ],
    });
    expect(res.status).toBe(409);
    expect(res.body.code).toBe('INSUFFICIENT_STOCK');
    expect(await prisma.stockMovement.count()).toBe(before);
    expect((await warehouseQty(f.warehouse.id, f.p1.id)).quantity).toBe(300);
  });

  it('adjustment reasons are required', async () => {
    const res = await api().post('/api/stock/adjustments').set(bearer(f.tokens.admin)).send({ locationType: 'WAREHOUSE', items: [{ productId: f.p1.id, quantity: 1 }] });
    expect(res.status).toBe(422);
  });

  it('negative stock is possible only when explicitly allowed in settings', async () => {
    await api().put('/api/settings').set(bearer(f.tokens.admin)).send({ allowNegativeStock: true });
    const res = await api().post('/api/stock/adjustments').set(bearer(f.tokens.admin)).send({ locationType: 'WAREHOUSE', reason: 'Test', items: [{ productId: f.p3.id, quantity: -2 }] });
    expect(res.status).toBe(201);
    expect((await warehouseQty(f.warehouse.id, f.p3.id)).quantity).toBe(-2);
    await api().post('/api/stock/adjustments').set(bearer(f.tokens.admin)).send({ locationType: 'WAREHOUSE', reason: 'Undo test', items: [{ productId: f.p3.id, quantity: 2 }] });
    await api().put('/api/settings').set(bearer(f.tokens.admin)).send({ allowNegativeStock: false });
  });

  it('damage moves units from available into the damaged bucket', async () => {
    await storeOpening(f, f.storeA.id, { [f.p1.id]: 10 });
    const res = await api().post('/api/stock/damage').set(bearer(f.tokens.a)).send({ locationType: 'STORE', storeId: f.storeA.id, items: [{ productId: f.p1.id, quantity: 3, reason: 'Broken' }] });
    expect(res.status).toBe(201);
    expect(await storeQty(f.storeA.id, f.p1.id)).toMatchObject({ quantity: 7, damagedQuantity: 3 });
    const woff = await api().post('/api/stock/damage/write-off').set(bearer(f.tokens.admin)).send({ locationType: 'STORE', storeId: f.storeA.id, items: [{ productId: f.p1.id, quantity: 4, reason: 'Dispose' }] });
    expect(woff.status).toBe(409);
  });

  it('movements list is filterable and scoped', async () => {
    const res = await api().get(`/api/stock/movements?productId=${f.p1.id}&type=DAMAGE`).set(bearer(f.tokens.a));
    expect(res.status).toBe(200);
    expect(res.body.data.length).toBe(2);
    expect(res.body.data.every((m: { storeId: string }) => m.storeId === f.storeA.id)).toBe(true);
    expect((await api().get('/api/stock/movements?locationType=WAREHOUSE').set(bearer(f.tokens.a))).status).toBe(403);
  });

  it('low stock notifications fire when crossing the minimum', async () => {
    await storeOpening(f, f.storeA.id, { [f.p3.id]: 6 });
    await api().post('/api/sales').set(bearer(f.tokens.a)).send({ paymentMethod: 'CASH', items: [{ productId: f.p3.id, quantity: 2 }] });
    const n = await prisma.notification.findFirst({ where: { userId: f.admin.id, type: 'LOW_STOCK' } });
    expect(n?.message).toContain('Product 3');
  });

  it('store availability submissions do not touch the ledger', async () => {
    const before = await prisma.stockMovement.count();
    const res = await api().post('/api/stock/availability').set(bearer(f.tokens.a)).send({ items: [{ productId: f.p1.id, quantity: 6 }] });
    expect(res.status).toBe(201);
    expect(await prisma.stockMovement.count()).toBe(before);
    const matrix = await api().get(`/api/stock/availability/matrix?search=Product 1`).set(bearer(f.tokens.admin));
    const row = matrix.body.data.rows.find((r: { product: { id: string } }) => r.product.id === f.p1.id);
    expect(row.stores.find((s: { storeId: string }) => s.storeId === f.storeA.id)).toMatchObject({ declaredQuantity: 6, systemQuantity: 7 });
  });

  it('removes a zero-balance stock record, but blocks removal while a balance remains', async () => {
    await api().post('/api/stock/purchases').set(bearer(f.tokens.admin)).send({ items: [{ productId: f.p3.id, quantity: 4 }] });
    const row = await prisma.warehouseStock.findFirstOrThrow({ where: { warehouseId: f.warehouse.id, productId: f.p3.id } });

    const blocked = await api().delete(`/api/stock/${row.id}?locationType=WAREHOUSE`).set(bearer(f.tokens.admin));
    expect(blocked.status).toBe(409);

    await api().post('/api/stock/adjustments').set(bearer(f.tokens.admin)).send({ locationType: 'WAREHOUSE', reason: 'Zero out for test', items: [{ productId: f.p3.id, quantity: -4 }] });

    expect((await api().delete(`/api/stock/${row.id}?locationType=WAREHOUSE`).set(bearer(f.tokens.a))).status).toBe(403);

    const removed = await api().delete(`/api/stock/${row.id}?locationType=WAREHOUSE`).set(bearer(f.tokens.admin));
    expect(removed.status).toBe(200);
    expect(await prisma.warehouseStock.findUnique({ where: { id: row.id } })).toBeNull();
    // The movements that produced the zero balance are untouched.
    expect(await prisma.stockMovement.count({ where: { productId: f.p3.id, warehouseId: f.warehouse.id } })).toBeGreaterThan(0);
  });

  it('ledger reconciles with cached balances', async () => {
    expect(await assertLedgerConsistent()).toBe(0);
  });
});
