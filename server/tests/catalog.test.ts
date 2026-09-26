import { beforeAll, describe, expect, it } from 'vitest';
import { api, bearer, buildFixture, Fixture } from './helpers';
import { prisma } from '../src/utils/prisma';

let f: Fixture;
beforeAll(async () => {
  f = await buildFixture();
});

describe('products', () => {
  let id: string;

  it('creates a product with validation', async () => {
    const bad = await api().post('/api/products').set(bearer(f.tokens.admin)).send({ name: 'X', sku: 'NEW1', categoryId: f.category.id, purchasePrice: -1, sellingPrice: 10, minimumStock: 10, maximumStock: 5 });
    expect(bad.status).toBe(422);
    const fields = bad.body.errors.map((e: { field: string }) => e.field);
    expect(fields).toEqual(expect.arrayContaining(['purchasePrice', 'maximumStock']));

    const res = await api().post('/api/products').set(bearer(f.tokens.admin)).send({ name: 'New Product', sku: 'new-1', barcode: '1234567890', categoryId: f.category.id, purchasePrice: 10, sellingPrice: 15.5, taxRate: 5, minimumStock: 3 });
    expect(res.status).toBe(201);
    expect(res.body.data.sku).toBe('NEW-1');
    id = res.body.data.id;
  });

  it('rejects duplicate SKU with 409', async () => {
    const res = await api().post('/api/products').set(bearer(f.tokens.admin)).send({ name: 'Dup', sku: 'NEW-1', categoryId: f.category.id, purchasePrice: 1, sellingPrice: 1 });
    expect(res.status).toBe(409);
    expect(res.body.code).toBe('CONFLICT');
  });

  it('lists with search, sort and pagination', async () => {
    const res = await api().get('/api/products?search=new&limit=1&page=1&sortBy=sellingPrice&sortOrder=desc').set(bearer(f.tokens.admin));
    expect(res.status).toBe(200);
    expect(res.body.pagination).toMatchObject({ page: 1, limit: 1, total: 1 });
    expect(res.body.data[0].name).toBe('New Product');
  });

  it('updates and audits price changes with old/new values', async () => {
    const res = await api().put(`/api/products/${id}`).set(bearer(f.tokens.admin)).send({ sellingPrice: 20 });
    expect(res.status).toBe(200);
    const log = await prisma.auditLog.findFirst({ where: { module: 'products', recordId: id, action: 'PRICE_CHANGE' } });
    expect(log?.oldValue).toMatchObject({ sellingPrice: '15.5' });
    expect(log?.newValue).toMatchObject({ sellingPrice: 20 });
  });

  it('deactivated products disappear from the store catalog', async () => {
    await api().patch(`/api/products/${id}/status`).set(bearer(f.tokens.admin)).send({ status: 'INACTIVE' });
    const store = await api().get('/api/products?search=new').set(bearer(f.tokens.a));
    expect(store.body.data).toHaveLength(0);
    const admin = await api().get('/api/products?search=new').set(bearer(f.tokens.admin));
    expect(admin.body.data).toHaveLength(1);
  });

  it('hard-deletes only products without history', async () => {
    const res = await api().delete(`/api/products/${id}`).set(bearer(f.tokens.admin));
    expect(res.body.data.deleted).toBe(true);
  });

  it('imports rows and reports row-level errors', async () => {
    const bad = await api().post('/api/products/import').set(bearer(f.tokens.admin)).send({ rows: [{ name: 'I1', sku: 'IMP-1', categoryCode: 'NOPE', purchasePrice: 1, sellingPrice: 2 }] });
    expect(bad.status).toBe(200);
    expect(bad.body.data.created).toBe(0);
    expect(bad.body.data.errors[0]).toMatchObject({ row: 2 });
    const ok = await api().post('/api/products/import').set(bearer(f.tokens.admin)).send({
      rows: [
        { name: 'I1', sku: 'IMP-1', categoryCode: 'cat', purchasePrice: '1', sellingPrice: '2' },
        { name: 'Product 1 renamed', sku: 'P1', categoryCode: 'CAT', purchasePrice: 50, sellingPrice: 100 },
      ],
    });
    expect(ok.status).toBe(200);
    expect(ok.body.data).toMatchObject({ created: 1, updated: 1 });
  });

  it('exports CSV with formula-injection protection', async () => {
    await prisma.product.update({ where: { id: f.p2.id }, data: { name: '=HYPERLINK("x")' } });
    const res = await api().get('/api/products/export?format=csv').set(bearer(f.tokens.admin));
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toContain('text/csv');
    expect(res.text).toContain(`"'=HYPERLINK(""x"")"`);
  });
});

describe('categories', () => {
  it('supports subcategories and filters products by parent', async () => {
    const sub = await api().post('/api/categories').set(bearer(f.tokens.admin)).send({ name: 'Sub', code: 'sub', parentId: f.category.id });
    expect(sub.status).toBe(201);
    await api().put(`/api/categories/${sub.body.data.id}/products`).set(bearer(f.tokens.admin)).send({ productIds: [f.p3.id] });
    const res = await api().get(`/api/products?categoryId=${f.category.id}&limit=50`).set(bearer(f.tokens.admin));
    expect(res.body.data.map((p: { id: string }) => p.id)).toContain(f.p3.id);
  });

  it('prevents category cycles', async () => {
    const sub = await prisma.category.findUniqueOrThrow({ where: { code: 'SUB' } });
    const res = await api().put(`/api/categories/${f.category.id}`).set(bearer(f.tokens.admin)).send({ parentId: sub.id });
    expect(res.status).toBe(422);
  });
});

describe('stores', () => {
  it('creates, updates, assigns a manager and toggles status', async () => {
    const res = await api().post('/api/stores').set(bearer(f.tokens.admin)).send({ name: 'Store D', code: 'std', city: 'Pune', email: '' });
    expect(res.status).toBe(201);
    const id = res.body.data.id;
    expect((await api().put(`/api/stores/${id}`).set(bearer(f.tokens.admin)).send({ phone: '+91 99999 00000' })).status).toBe(200);
    expect((await api().put(`/api/stores/${id}/manager`).set(bearer(f.tokens.admin)).send({ managerId: f.userA.id })).status).toBe(422);
    expect((await api().put(`/api/stores/${id}/manager`).set(bearer(f.tokens.admin)).send({ managerId: f.m2.id })).status).toBe(200);
    expect((await api().patch(`/api/stores/${id}/status`).set(bearer(f.tokens.admin)).send({ status: 'INACTIVE' })).status).toBe(200);
    const m2 = await api().get('/api/stores').set(bearer(f.tokens.m2));
    expect(m2.body.data.map((s: { code: string }) => s.code)).toContain('STD');
  });

  it('rejects duplicate store codes', async () => {
    const res = await api().post('/api/stores').set(bearer(f.tokens.admin)).send({ name: 'Dup', code: 'STA' });
    expect(res.status).toBe(409);
  });

  it('hard-deletes a clean store, but deactivates one with history instead', async () => {
    const created = await api().post('/api/stores').set(bearer(f.tokens.admin)).send({ name: 'Temp Store', code: 'tmp1' });
    const cleanId = created.body.data.id;
    const del = await api().delete(`/api/stores/${cleanId}`).set(bearer(f.tokens.admin));
    expect(del.status).toBe(200);
    expect(del.body.data).toMatchObject({ deleted: true, deactivated: false });
    expect((await api().get(`/api/stores/${cleanId}`).set(bearer(f.tokens.admin))).status).toBe(404);

    // storeA already has a store user (userA) assigned - that counts as history.
    const del2 = await api().delete(`/api/stores/${f.storeA.id}`).set(bearer(f.tokens.admin));
    expect(del2.status).toBe(200);
    expect(del2.body.data).toMatchObject({ deleted: false, deactivated: true });
    const check = await api().get(`/api/stores/${f.storeA.id}`).set(bearer(f.tokens.admin));
    expect(check.body.data.status).toBe('INACTIVE');
    await api().patch(`/api/stores/${f.storeA.id}/status`).set(bearer(f.tokens.admin)).send({ status: 'ACTIVE' });
  });

  it('managers cannot delete stores', async () => {
    expect((await api().delete(`/api/stores/${f.storeB.id}`).set(bearer(f.tokens.m1))).status).toBe(403);
  });
});

describe('users', () => {
  it('store users must have a store; managers may only create store users for their stores', async () => {
    const noStore = await api().post('/api/users').set(bearer(f.tokens.admin)).send({ name: 'X', email: 'x@test.local', password: 'Passw0rd!', role: 'STORE' });
    expect(noStore.status).toBe(422);

    await api().put(`/api/managers/${f.m1.id}/permissions`).set(bearer(f.tokens.admin)).send({ permissions: ['users.manage'] });
    const ok = await api().post('/api/users').set(bearer(f.tokens.m1)).send({ name: 'New A', email: 'newa@test.local', password: 'Passw0rd!', role: 'STORE', storeId: f.storeA.id });
    expect(ok.status).toBe(201);
    const otherStore = await api().post('/api/users').set(bearer(f.tokens.m1)).send({ name: 'New C', email: 'newc@test.local', password: 'Passw0rd!', role: 'STORE', storeId: f.storeC.id });
    expect(otherStore.status).toBe(403);
    const manager = await api().post('/api/users').set(bearer(f.tokens.m1)).send({ name: 'Boss', email: 'boss@test.local', password: 'Passw0rd!', role: 'ADMIN' });
    expect(manager.status).toBe(403);
  });

  it('deletes a clean account, deactivates one with activity, and blocks removing a manager with assigned stores', async () => {
    const created = await api().post('/api/users').set(bearer(f.tokens.admin)).send({ name: 'Fresh', email: 'fresh@test.local', password: 'Passw0rd!', role: 'STORE', storeId: f.storeA.id });
    const freshId = created.body.data.id;
    const del = await api().delete(`/api/users/${freshId}`).set(bearer(f.tokens.admin));
    expect(del.status).toBe(200);
    expect(del.body.data).toMatchObject({ deleted: true, deactivated: false });
    expect((await api().get(`/api/users/${freshId}`).set(bearer(f.tokens.admin))).status).toBe(404);

    // userC has already logged in (during fixture setup), so it has audit history.
    const del2 = await api().delete(`/api/users/${f.userC.id}`).set(bearer(f.tokens.admin));
    expect(del2.status).toBe(200);
    expect(del2.body.data).toMatchObject({ deleted: false, deactivated: true });
    const check = await api().get(`/api/users/${f.userC.id}`).set(bearer(f.tokens.admin));
    expect(check.body.data.status).toBe('INACTIVE');
    await api().patch(`/api/users/${f.userC.id}/status`).set(bearer(f.tokens.admin)).send({ status: 'ACTIVE' });

    // m1 currently manages storeA and storeB - must be reassigned before removal.
    expect((await api().delete(`/api/users/${f.m1.id}`).set(bearer(f.tokens.admin))).status).toBe(409);

    // cannot delete your own account
    expect((await api().delete(`/api/users/${f.admin.id}`).set(bearer(f.tokens.admin))).status).toBe(400);
  });
});
