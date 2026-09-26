import { beforeAll, describe, expect, it } from 'vitest';
import { api, assertLedgerConsistent, bearer, buildFixture, Fixture, storeOpening, storeQty } from './helpers';
import { prisma } from '../src/utils/prisma';

let f: Fixture;
beforeAll(async () => {
  f = await buildFixture();
  await storeOpening(f, f.storeA.id, { [f.p1.id]: 20, [f.p2.id]: 5 });
});

describe('sales', () => {
  let saleId: string;

  it('records a sale atomically with server-computed totals', async () => {
    const res = await api().post('/api/sales').set(bearer(f.tokens.a)).send({
      customerName: 'Walk-in',
      paymentMethod: 'UPI',
      discount: 10,
      items: [{ productId: f.p1.id, quantity: 2, discount: 20 }, { productId: f.p2.id, quantity: 1 }],
    });
    expect(res.status).toBe(201);
    const s = res.body.data;
    saleId = s.id;
    // P1: 2 × 100 − 20 = 180, tax 10% = 18 → 198 · P2: 100 + 10 = 110 · subtotal 280, tax 28, −10 → 298
    expect(s).toMatchObject({ subtotal: '280', tax: '28', discount: '10', grandTotal: '298' });
    expect(s.invoiceNumber).toBe('INV-STA-000001');
    expect(await storeQty(f.storeA.id, f.p1.id)).toMatchObject({ quantity: 18 });
    const movement = await prisma.stockMovement.findFirst({ where: { referenceType: 'SALE', referenceId: saleId, productId: f.p1.id } });
    expect(movement).toMatchObject({ type: 'SALE', quantity: -2, balanceAfter: 18 });
  });

  it('rolls back everything when any line lacks stock', async () => {
    const salesBefore = await prisma.sale.count();
    const res = await api().post('/api/sales').set(bearer(f.tokens.a)).send({
      paymentMethod: 'CASH',
      items: [{ productId: f.p1.id, quantity: 1 }, { productId: f.p2.id, quantity: 999 }],
    });
    expect(res.status).toBe(409);
    expect(res.body.code).toBe('INSUFFICIENT_STOCK');
    expect(await prisma.sale.count()).toBe(salesBefore);
    expect((await storeQty(f.storeA.id, f.p1.id)).quantity).toBe(18);
  });

  it('price overrides are blocked for store users by default', async () => {
    const res = await api().post('/api/sales').set(bearer(f.tokens.a)).send({ paymentMethod: 'CASH', items: [{ productId: f.p1.id, quantity: 1, unitPrice: 1 }] });
    expect(res.status).toBe(422);
  });

  it('is idempotent on clientRequestId (no duplicate sale, no double stock deduction)', async () => {
    const body = { paymentMethod: 'CASH', clientRequestId: 'sale-retry-0001', items: [{ productId: f.p1.id, quantity: 1 }] };
    const first = await api().post('/api/sales').set(bearer(f.tokens.a)).send(body);
    const retry = await api().post('/api/sales').set(bearer(f.tokens.a)).send(body);
    expect(first.status).toBe(201);
    expect(retry.status).toBe(200);
    expect(retry.body.data.id).toBe(first.body.data.id);
    expect((await storeQty(f.storeA.id, f.p1.id)).quantity).toBe(17);
  });

  it('concurrent sales can never oversell', async () => {
    // 17 units left; 10 parallel sales of 3 → at most 5 succeed.
    const results = await Promise.all(
      Array.from({ length: 10 }, () => api().post('/api/sales').set(bearer(f.tokens.a)).send({ paymentMethod: 'CASH', items: [{ productId: f.p1.id, quantity: 3 }] })),
    );
    const ok = results.filter((r) => r.status === 201).length;
    expect(ok).toBe(5);
    expect(results.filter((r) => r.status !== 201).every((r) => r.body.code === 'INSUFFICIENT_STOCK')).toBe(true);
    expect((await storeQty(f.storeA.id, f.p1.id)).quantity).toBe(2);
  });

  it('lists sales with summary and filters', async () => {
    const res = await api().get('/api/sales?paymentMethod=UPI').set(bearer(f.tokens.a));
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.summary.completedCount).toBe(1);
  });
});

describe('returns', () => {
  let saleId: string;
  beforeAll(async () => {
    const sale = await prisma.sale.findFirstOrThrow({ where: { invoiceNumber: 'INV-STA-000001' } });
    saleId = sale.id;
  });

  it('good returns go back to available stock at the sold price', async () => {
    const res = await api().post('/api/returns').set(bearer(f.tokens.a)).send({ saleId, items: [{ productId: f.p1.id, quantity: 1, condition: 'GOOD', reason: 'Changed mind' }] });
    expect(res.status).toBe(201);
    expect(res.body.data.refundAmount).toBe('99'); // 198 / 2
    expect((await storeQty(f.storeA.id, f.p1.id)).quantity).toBe(3);
  });

  it('damaged returns go into damaged stock', async () => {
    const res = await api().post('/api/returns').set(bearer(f.tokens.a)).send({ saleId, items: [{ productId: f.p2.id, quantity: 1, condition: 'DAMAGED', reason: 'Broken seal' }] });
    expect(res.status).toBe(201);
    expect(await storeQty(f.storeA.id, f.p2.id)).toMatchObject({ quantity: 4, damagedQuantity: 1 });
  });

  it('cannot return more than was sold (minus earlier returns)', async () => {
    const res = await api().post('/api/returns').set(bearer(f.tokens.a)).send({ saleId, items: [{ productId: f.p1.id, quantity: 2, condition: 'GOOD', reason: 'x' }] });
    expect(res.status).toBe(422);
    expect(res.body.errors[0].message).toContain('Only 1');
  });

  it('cannot return against another store sale', async () => {
    await storeOpening(f, f.storeB.id, { [f.p1.id]: 5 });
    const res = await api().post('/api/returns').set(bearer(f.tokens.b)).send({ saleId, items: [{ productId: f.p1.id, quantity: 1, condition: 'GOOD', reason: 'x' }] });
    expect(res.status).toBe(422);
  });

  it('sales with returns cannot be cancelled; others restore stock on cancel', async () => {
    expect((await api().put(`/api/sales/${saleId}/cancel`).set(bearer(f.tokens.admin)).send({ reason: 'Void' })).status).toBe(409);
    const sale = await api().post('/api/sales').set(bearer(f.tokens.b)).send({ paymentMethod: 'CASH', items: [{ productId: f.p1.id, quantity: 2 }] });
    expect((await storeQty(f.storeB.id, f.p1.id)).quantity).toBe(3);
    // Store users lack sales.cancel.
    expect((await api().put(`/api/sales/${sale.body.data.id}/cancel`).set(bearer(f.tokens.b)).send({ reason: 'Void' })).status).toBe(403);
    const res = await api().put(`/api/sales/${sale.body.data.id}/cancel`).set(bearer(f.tokens.admin)).send({ reason: 'Entered twice' });
    expect(res.body.data.status).toBe('CANCELLED');
    expect((await storeQty(f.storeB.id, f.p1.id)).quantity).toBe(5);
  });

  it('ledger reconciles', async () => {
    expect(await assertLedgerConsistent()).toBe(0);
  });
});

describe('reports & dashboard', () => {
  it('dashboard is role-aware', async () => {
    const admin = await api().get('/api/dashboard').set(bearer(f.tokens.admin));
    expect(admin.body.data.scope).toBe('ALL');
    const store = await api().get('/api/dashboard').set(bearer(f.tokens.a));
    expect(store.body.data.scope).toBe('STORE');
    expect(store.body.data.cards.warehouseStock).toBeUndefined();
  });

  it('reports export as CSV, XLSX and PDF', async () => {
    for (const [format, type] of [['csv', 'text/csv'], ['xlsx', 'spreadsheetml'], ['pdf', 'application/pdf']]) {
      const res = await api().get(`/api/reports/sales?groupBy=product&format=${format}`).set(bearer(f.tokens.admin)).buffer(true);
      expect(res.status).toBe(200);
      expect(res.headers['content-type']).toContain(type);
      expect(res.headers['content-disposition']).toContain(`.${format}`);
    }
  });

  it('all stock report types run', async () => {
    for (const type of ['current', 'low', 'movement', 'store', 'warehouse', 'damaged', 'returned', 'valuation']) {
      const res = await api().get(`/api/reports/stock?type=${type}`).set(bearer(f.tokens.admin));
      expect(res.status, type).toBe(200);
    }
    expect((await api().get('/api/reports/stock?type=warehouse').set(bearer(f.tokens.a))).status).toBe(403);
    const val = await api().get('/api/reports/stock?type=valuation').set(bearer(f.tokens.a));
    expect(val.body.data.columns.map((c: { key: string }) => c.key)).not.toContain('costValue');
  });
});
