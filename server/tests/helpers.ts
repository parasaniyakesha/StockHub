import request from 'supertest';
import { Role } from '@prisma/client';
import app from '../src/app';
import { prisma } from '../src/utils/prisma';
import { hashPassword } from '../src/utils/crypto';
import { DEFAULT_MANAGER_PERMISSIONS } from '../src/config/permissions';

export const api = () => request(app);
export const PASSWORD = 'Test@12345';

const TABLES = [
  'notifications', 'audit_logs', 'stock_movements', 'return_items', 'returns', 'sale_items', 'sales',
  'stock_transfer_items', 'stock_transfers', 'packing_order_store_items', 'packing_order_stores', 'packing_order_items',
  'packing_orders', 'product_request_items', 'product_requests', 'store_availability', 'store_stock', 'warehouse_stock',
  'products', 'categories', 'refresh_tokens', 'password_reset_tokens', 'users', 'stores', 'warehouses', 'settings', 'counters',
];

export async function resetDb() {
  await prisma.$executeRawUnsafe(`TRUNCATE ${TABLES.map((t) => `"${t}"`).join(', ')} RESTART IDENTITY CASCADE`);
}

/**
 * Fixture:
 *   Manager M1 → Store A, Store B        Manager M2 → Store C
 *   Store users: userA (A), userB (B), userC (C)
 *   Products P1, P2, P3 (P3 has minimumStock 5)
 */
export async function buildFixture() {
  await resetDb();
  const hash = await hashPassword(PASSWORD);
  const warehouse = await prisma.warehouse.create({ data: { code: 'WH', name: 'Test Warehouse', isDefault: true } });
  const admin = await prisma.user.create({ data: { name: 'Admin', email: 'admin@test.local', passwordHash: hash, role: Role.ADMIN } });
  const m1 = await prisma.user.create({ data: { name: 'Manager One', email: 'm1@test.local', passwordHash: hash, role: Role.MANAGER, permissions: DEFAULT_MANAGER_PERMISSIONS } });
  const m2 = await prisma.user.create({ data: { name: 'Manager Two', email: 'm2@test.local', passwordHash: hash, role: Role.MANAGER, permissions: DEFAULT_MANAGER_PERMISSIONS } });
  const storeA = await prisma.store.create({ data: { code: 'STA', name: 'Store A', assignedManagerId: m1.id } });
  const storeB = await prisma.store.create({ data: { code: 'STB', name: 'Store B', assignedManagerId: m1.id } });
  const storeC = await prisma.store.create({ data: { code: 'STC', name: 'Store C', assignedManagerId: m2.id } });
  const userA = await prisma.user.create({ data: { name: 'User A', email: 'a@test.local', passwordHash: hash, role: Role.STORE, storeId: storeA.id } });
  const userB = await prisma.user.create({ data: { name: 'User B', email: 'b@test.local', passwordHash: hash, role: Role.STORE, storeId: storeB.id } });
  const userC = await prisma.user.create({ data: { name: 'User C', email: 'c@test.local', passwordHash: hash, role: Role.STORE, storeId: storeC.id } });
  const category = await prisma.category.create({ data: { code: 'CAT', name: 'Category' } });
  const mk = (n: number, extra: object = {}) =>
    prisma.product.create({
      data: { name: `Product ${n}`, sku: `P${n}`, categoryId: category.id, purchasePrice: 50, sellingPrice: 100, taxRate: 10, ...extra },
    });
  const [p1, p2, p3] = [await mk(1), await mk(2), await mk(3, { minimumStock: 5 })];

  const tokens = {
    admin: await login('admin@test.local'),
    m1: await login('m1@test.local'),
    m2: await login('m2@test.local'),
    a: await login('a@test.local'),
    b: await login('b@test.local'),
    c: await login('c@test.local'),
  };
  return { warehouse, admin, m1, m2, storeA, storeB, storeC, userA, userB, userC, category, p1, p2, p3, tokens };
}

export type Fixture = Awaited<ReturnType<typeof buildFixture>>;

export async function login(email: string, password = PASSWORD) {
  const res = await api().post('/api/auth/login').send({ email, password });
  if (res.status !== 200) throw new Error(`Login failed for ${email}: ${res.status} ${JSON.stringify(res.body)}`);
  return res.body.data.accessToken as string;
}

export const bearer = (token: string) => ({ Authorization: `Bearer ${token}` });

/** Put stock into the warehouse (opening) and optionally into stores via the ledger. */
export async function stockUp(f: Fixture, warehouseQty: Record<string, number>) {
  const res = await api()
    .post('/api/stock/opening')
    .set(bearer(f.tokens.admin))
    .send({ locationType: 'WAREHOUSE', items: Object.entries(warehouseQty).map(([productId, quantity]) => ({ productId, quantity })) });
  if (res.status !== 201) throw new Error(JSON.stringify(res.body));
}

export async function storeOpening(f: Fixture, storeId: string, qty: Record<string, number>) {
  const res = await api()
    .post('/api/stock/opening')
    .set(bearer(f.tokens.admin))
    .send({ locationType: 'STORE', storeId, items: Object.entries(qty).map(([productId, quantity]) => ({ productId, quantity })) });
  if (res.status !== 201) throw new Error(JSON.stringify(res.body));
}

export const storeQty = async (storeId: string, productId: string) =>
  (await prisma.storeStock.findUnique({ where: { storeId_productId: { storeId, productId } } })) ?? { quantity: 0, damagedQuantity: 0, reservedQuantity: 0 };

export const warehouseQty = async (warehouseId: string, productId: string) =>
  (await prisma.warehouseStock.findUnique({ where: { warehouseId_productId: { warehouseId, productId } } })) ?? { quantity: 0, damagedQuantity: 0, reservedQuantity: 0 };

/** Every cached balance must equal the sum of its ledger movements. */
export async function assertLedgerConsistent() {
  const rows = await prisma.$queryRaw<{ n: bigint }[]>`
    SELECT COUNT(*) AS n FROM (
      SELECT s.quantity AS cached, COALESCE((SELECT SUM(quantity) FROM stock_movements m WHERE m."storeId"=s."storeId" AND m."productId"=s."productId" AND bucket='AVAILABLE'),0) AS ledger FROM store_stock s
      UNION ALL
      SELECT s."damagedQuantity", COALESCE((SELECT SUM(quantity) FROM stock_movements m WHERE m."storeId"=s."storeId" AND m."productId"=s."productId" AND bucket='DAMAGED'),0) FROM store_stock s
      UNION ALL
      SELECT w.quantity, COALESCE((SELECT SUM(quantity) FROM stock_movements m WHERE m."warehouseId"=w."warehouseId" AND m."productId"=w."productId" AND bucket='AVAILABLE'),0) FROM warehouse_stock w
    ) x WHERE cached <> ledger`;
  return Number(rows[0].n);
}
