/**
 * Development seed. Builds clearly-fake demo data THROUGH THE SERVICE LAYER so every
 * unit of stock has matching ledger movements and every workflow is exercised:
 *   1 admin · 2 managers · 5 stores · 20 store users · 5 categories · 50 products
 *   warehouse opening stock + purchases · store stock via packing orders
 *   product requests (all stages) · transfers · 30 days of sales · returns · damage
 *
 * Refuses to run when NODE_ENV=production. Skips if data already exists
 * (use `npm run db:reset` to rebuild from scratch).
 */
import { PaymentMethod, Product, Role, Store } from '@prisma/client';
import { prisma } from '../src/utils/prisma';
import { hashPassword, randomToken } from '../src/utils/crypto';
import { resolveScope } from '../src/middleware/authenticate';
import { effectivePermissions, DEFAULT_MANAGER_PERMISSIONS, PERMISSIONS } from '../src/config/permissions';
import { RequestContext } from '../src/types/auth';
import * as stock from '../src/services/stock.service';
import * as requests from '../src/services/productRequest.service';
import * as packing from '../src/services/packingOrder.service';
import * as transfers from '../src/services/transfer.service';
import * as sales from '../src/services/sale.service';
import * as returns from '../src/services/return.service';

if (process.env.NODE_ENV === 'production') {
  console.error('Refusing to seed a production database.');
  process.exit(1);
}




const adminEmail = (process.env.SEED_ADMIN_EMAIL ?? 'admin@gmail.com').toLowerCase();
const adminPassword = process.env.SEED_ADMIN_PASSWORD || `Adm!${randomToken(9)}9a`;
const defaultPassword = process.env.SEED_DEFAULT_PASSWORD || `Usr!${randomToken(9)}9a`;

// Deterministic pseudo-random numbers so the seed is reproducible.
let seed = 42;
const rand = () => ((seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296);
const int = (min: number, max: number) => Math.floor(rand() * (max - min + 1)) + min;
const pick = <T>(arr: T[]) => arr[Math.floor(rand() * arr.length)];

async function contextFor(userId: string): Promise<RequestContext> {
  const u = await prisma.user.findUniqueOrThrow({ where: { id: userId } });
  return {
    user: { id: u.id, name: u.name, email: u.email, role: u.role, storeId: u.storeId, permissions: effectivePermissions(u.role, u.permissions) },
    scope: await resolveScope(u.id, u.role, u.storeId),
    ip: '127.0.0.1',
    userAgent: 'seed-script',
  };
}

const CATEGORIES = [
  { code: 'GROC', name: 'Groceries', products: ['Basmati Rice 5kg', 'Whole Wheat Atta 10kg', 'Toor Dal 1kg', 'Sunflower Oil 1L', 'Sugar 1kg', 'Iodised Salt 1kg', 'Poha 500g', 'Moong Dal 1kg', 'Besan 1kg', 'Rava 1kg'] },
  { code: 'BEV', name: 'Beverages', products: ['Assam Tea 500g', 'Instant Coffee 100g', 'Mango Drink 1L', 'Mineral Water 1L', 'Green Tea 25 bags', 'Orange Juice 1L', 'Energy Drink 250ml', 'Lassi 200ml', 'Cola 750ml', 'Buttermilk 500ml'] },
  { code: 'CARE', name: 'Personal Care', products: ['Herbal Shampoo 340ml', 'Neem Soap 4x100g', 'Toothpaste 150g', 'Hand Wash 250ml', 'Face Wash 100ml', 'Coconut Hair Oil 300ml', 'Body Lotion 400ml', 'Shaving Foam 200g', 'Toothbrush Soft', 'Talcum Powder 300g'] },
  { code: 'HOME', name: 'Household', products: ['Detergent Powder 1kg', 'Dishwash Liquid 500ml', 'Floor Cleaner 1L', 'Toilet Cleaner 500ml', 'Garbage Bags 30pc', 'Scrub Pad 3pc', 'Glass Cleaner 500ml', 'Mosquito Coil 10pc', 'Air Freshener 250ml', 'Kitchen Towel 2 roll'] },
  { code: 'SNK', name: 'Snacks', products: ['Salted Chips 150g', 'Masala Namkeen 400g', 'Cream Biscuits 300g', 'Chocolate Bar 50g', 'Roasted Peanuts 200g', 'Instant Noodles 4pk', 'Marie Biscuits 250g', 'Popcorn 100g', 'Khakhra 200g', 'Dry Fruit Mix 250g'] },
];

const STORES = [
  { code: 'DEMO-AHM', name: 'Demo Store Ahmedabad', city: 'Ahmedabad' },
  { code: 'DEMO-SUR', name: 'Demo Store Surat', city: 'Surat' },
  { code: 'DEMO-VAD', name: 'Demo Store Vadodara', city: 'Vadodara' },
  { code: 'DEMO-RAJ', name: 'Demo Store Rajkot', city: 'Rajkot' },
  { code: 'DEMO-MUM', name: 'Demo Store Mumbai', city: 'Mumbai' },
];

async function main() {
  if (await prisma.user.count()) {
    console.log('Database already contains data - skipping seed. Run `npm run db:reset` to rebuild.');
    return;
  }

  console.log('Seeding StockHub development data…');
  const warehouse = await prisma.warehouse.create({
    data: { code: 'CWH-01', name: 'Central Warehouse (Demo)', address: 'Plot 1, Demo Industrial Estate', isDefault: true },
  });

  const [adminHash, userHash] = await Promise.all([hashPassword(adminPassword), hashPassword(defaultPassword)]);

  const admin = await prisma.user.create({ data: { name: 'Demo Admin', email: adminEmail, passwordHash: adminHash, role: Role.ADMIN } });
  const managerA = await prisma.user.create({
    data: { name: 'Demo Manager West', email: 'manager.west@example.com', passwordHash: userHash, role: Role.MANAGER, permissions: [...DEFAULT_MANAGER_PERMISSIONS, PERMISSIONS.STOCK_ADJUST, PERMISSIONS.USERS_MANAGE] },
  });
  const managerB = await prisma.user.create({
    data: { name: 'Demo Manager Metro', email: 'manager.metro@example.com', passwordHash: userHash, role: Role.MANAGER, permissions: DEFAULT_MANAGER_PERMISSIONS },
  });

  // Manager West: Ahmedabad, Surat, Vadodara. Manager Metro: Rajkot, Mumbai.
  const stores: Store[] = [];
  for (const [i, s] of STORES.entries()) {
    stores.push(
      await prisma.store.create({
        data: {
          ...s,
          address: `${100 + i}, Demo Market Road`,
          phone: `+91 90000 0000${i}`,
          email: `${s.code.toLowerCase()}@example.com`,
          contactPerson: `Demo Contact ${i + 1}`,
          assignedManagerId: i < 3 ? managerA.id : managerB.id,
        },
      }),
    );
  }

  // 4 store users per store = 20.
  const storeUsers: Record<string, string[]> = {};
  for (const store of stores) {
    storeUsers[store.id] = [];
    const slug = store.code.split('-')[1].toLowerCase();
    for (let n = 1; n <= 4; n++) {
      const u = await prisma.user.create({
        data: { name: `${store.city} Staff ${n}`, email: `${slug}.staff${n}@example.com`, passwordHash: userHash, role: Role.STORE, storeId: store.id },
      });
      storeUsers[store.id].push(u.id);
    }
  }

  // Categories & products.
  const products: Product[] = [];
  let skuNo = 1;
  for (const c of CATEGORIES) {
    const category = await prisma.category.create({ data: { code: c.code, name: c.name, description: `${c.name} (demo category)` } });
    for (const name of c.products) {
      const cost = int(20, 450);
      products.push(
        await prisma.product.create({
          data: {
            name,
            sku: `DEMO-${String(skuNo).padStart(3, '0')}`,
            barcode: `890000000${String(skuNo).padStart(4, '0')}`,
            categoryId: category.id,
            brand: pick(['DemoBrand', 'SampleCo', 'TestMart', 'Acme Demo']),
            unit: 'PCS',
            description: `Demo product for development - ${name}`,
            purchasePrice: cost,
            sellingPrice: Math.round(cost * (1.2 + rand() * 0.3)),
            taxRate: pick([0, 5, 12, 18]),
            minimumStock: int(5, 20),
            maximumStock: int(150, 400),
          },
        }),
      );
      skuNo++;
    }
  }
  // A couple of subcategories to demonstrate the tree.
  const groc = await prisma.category.findUniqueOrThrow({ where: { code: 'GROC' } });
  await prisma.category.create({ data: { code: 'GROC-PULSE', name: 'Pulses & Dals', parentId: groc.id } });
  await prisma.category.create({ data: { code: 'GROC-FLOUR', name: 'Flours', parentId: groc.id } });

  const adminCtx = await contextFor(admin.id);

  // ── Warehouse stock: opening + a purchase ──
  await stock.recordOpeningStock(adminCtx, {
    locationType: 'WAREHOUSE',
    warehouseId: warehouse.id,
    reason: 'Opening stock (demo)',
    items: products.map((p) => ({ productId: p.id, quantity: int(400, 900) })),
  });
  await stock.recordPurchase(adminCtx, {
    warehouseId: warehouse.id,
    supplierReference: 'DEMO-PUR-0001',
    items: products.slice(0, 20).map((p) => ({ productId: p.id, quantity: int(100, 250) })),
  });

  // ── Stores request stock → approve → packing order → pack → dispatch → receive ──
  const approvedRequestIds: string[] = [];
  for (const store of stores) {
    const staff = await contextFor(storeUsers[store.id][0]);
    const lines = [...products].sort(() => rand() - 0.5).slice(0, 30);
    const req = await requests.createRequest(staff, {
      notes: 'Initial stocking request (demo)',
      submit: true,
      items: lines.map((p) => ({ productId: p.id, requestedQuantity: int(60, 120) })),
    });
    const reviewer = await contextFor(store.assignedManagerId!);
    const approved = await requests.approveRequest(reviewer, req.id, {
      reviewNotes: 'Approved for initial stocking',
      items: req.items.map((i, idx) => ({ itemId: i.id, approvedQuantity: idx % 7 === 0 ? Math.floor(i.requestedQuantity * 0.8) : i.requestedQuantity })),
    });
    approvedRequestIds.push(approved.id);
  }
  // One multi-store packing order for the first three stores, one for the rest.
  for (const batch of [approvedRequestIds.slice(0, 3), approvedRequestIds.slice(3)]) {
    const order = await packing.createFromRequests(adminCtx, { requestIds: batch, warehouseId: warehouse.id });
    await packing.assignPackingOrder(adminCtx, order.id);
    await packing.startPacking(adminCtx, order.id);
    await packing.markPacked(adminCtx, order.id, {});
    await packing.dispatchPackingOrder(adminCtx, order.id);
    for (const section of order.stores) {
      const staff = await contextFor(storeUsers[section.storeId][1]);
      await packing.receivePackingOrder(staff, order.id, {});
    }
  }

  // ── Requests left at different stages for the UI ──
  const s0 = await contextFor(storeUsers[stores[0].id][0]);
  const s1 = await contextFor(storeUsers[stores[1].id][0]);
  const s3 = await contextFor(storeUsers[stores[3].id][0]);
  await requests.createRequest(s0, { notes: 'Weekend top-up (draft)', items: products.slice(0, 3).map((p) => ({ productId: p.id, requestedQuantity: 25 })), submit: false });
  await requests.createRequest(s1, { notes: 'Festival demand', items: products.slice(10, 15).map((p) => ({ productId: p.id, requestedQuantity: 40 })), submit: true });
  const underReview = await requests.createRequest(s3, { notes: 'Low on snacks', items: products.slice(40, 44).map((p) => ({ productId: p.id, requestedQuantity: 30 })), submit: true });
  await requests.startReview(await contextFor(managerB.id), underReview.id);
  const toPack = await requests.createRequest(s0, { notes: 'Beverages restock', items: products.slice(10, 14).map((p) => ({ productId: p.id, requestedQuantity: 50 })), submit: true });
  const approvedPending = await requests.approveRequest(await contextFor(managerA.id), toPack.id, {
    items: toPack.items.map((i, idx) => ({ itemId: i.id, approvedQuantity: idx === 0 ? 40 : i.requestedQuantity })),
  });

  // Packing orders in progress: one assigned (from request), one manual draft allocating to 3 stores.
  const pendingOrder = await packing.createFromRequests(adminCtx, { requestIds: [approvedPending.id], warehouseId: warehouse.id });
  await packing.assignPackingOrder(adminCtx, pendingOrder.id);
  await packing.createPackingOrder(adminCtx, {
    warehouseId: warehouse.id,
    notes: 'Manual allocation - new product launch (demo)',
    items: products.slice(20, 23).map((p) => ({ productId: p.id, quantity: 90 })),
    stores: stores.slice(0, 3).map((s) => ({ storeId: s.id, items: products.slice(20, 23).map((p) => ({ productId: p.id, allocatedQuantity: 30 })) })),
  });
  // One dispatched and awaiting receipt at Mumbai.
  const inTransit = await packing.createPackingOrder(adminCtx, {
    warehouseId: warehouse.id,
    items: products.slice(30, 33).map((p) => ({ productId: p.id, quantity: 20 })),
    stores: [{ storeId: stores[4].id, items: products.slice(30, 33).map((p) => ({ productId: p.id, allocatedQuantity: 20 })) }],
  });
  await packing.assignPackingOrder(adminCtx, inTransit.id);
  await packing.markPacked(adminCtx, inTransit.id, {});
  await packing.dispatchPackingOrder(adminCtx, inTransit.id);

  // ── Store availability submissions ──
  for (const store of stores) {
    const staff = await contextFor(storeUsers[store.id][2]);
    const levels = await prisma.storeStock.findMany({ where: { storeId: store.id }, take: 15 });
    await stock.submitAvailability(staff, { notes: 'Shelf count (demo)', items: levels.map((l) => ({ productId: l.productId, quantity: Math.max(l.quantity - int(0, 5), 0) })) });
  }

  // ── Sales over the last 30 days (backdated for charts) ──
  const methods: PaymentMethod[] = ['CASH', 'CARD', 'UPI', 'UPI', 'CASH'];
  let saleCount = 0;
  const saleIds: { id: string; storeId: string }[] = [];
  for (let day = 29; day >= 0; day--) {
    for (const store of stores) {
      const perDay = int(1, 3);
      for (let k = 0; k < perDay; k++) {
        const staffCtx = await contextFor(pick(storeUsers[store.id]));
        const levels = await prisma.storeStock.findMany({ where: { storeId: store.id, quantity: { gt: 10 } } });
        if (!levels.length) continue;
        const lines = [...levels].sort(() => rand() - 0.5).slice(0, int(1, 4));
        try {
          const { sale } = await sales.createSale(staffCtx, {
            customerName: rand() > 0.5 ? `Demo Customer ${int(1, 999)}` : undefined,
            paymentMethod: pick(methods),
            discount: 0,
            items: lines.map((l) => ({ productId: l.productId, quantity: int(1, 3), discount: 0 })),
          });
          const when = new Date(Date.now() - day * 86_400_000 - int(0, 8) * 3_600_000);
          await prisma.sale.update({ where: { id: sale.id }, data: { createdAt: when } });
          await prisma.stockMovement.updateMany({ where: { referenceType: 'SALE', referenceId: sale.id }, data: { createdAt: when } });
          saleIds.push({ id: sale.id, storeId: store.id });
          saleCount++;
        } catch {
          // Skip lines that would oversell - ledger protects stock.
        }
      }
    }
  }

  // ── Returns and damage ──
  for (const s of saleIds.slice(0, 6)) {
    const sale = await prisma.sale.findUniqueOrThrow({ where: { id: s.id }, include: { items: true } });
    const staffCtx = await contextFor(storeUsers[s.storeId][0]);
    const item = sale.items[0];
    await returns.createReturn(staffCtx, {
      saleId: sale.id,
      notes: 'Customer return (demo)',
      items: [{ productId: item.productId, quantity: 1, condition: saleIds.indexOf(s) % 2 ? 'DAMAGED' : 'GOOD', reason: saleIds.indexOf(s) % 2 ? 'Packaging torn' : 'Customer changed mind' }],
    });
  }
  for (const store of stores.slice(0, 3)) {
    const staffCtx = await contextFor(storeUsers[store.id][3]);
    const level = await prisma.storeStock.findFirstOrThrow({ where: { storeId: store.id, quantity: { gt: 5 } } });
    await stock.reportDamage(staffCtx, { locationType: 'STORE', storeId: store.id, items: [{ productId: level.productId, quantity: 2, reason: 'Water damage on shelf (demo)' }] });
  }

  // ── Transfers: completed store→store, approved, requested, warehouse→store dispatched ──
  const ahm = stores[0];
  const sur = stores[1];
  const ahmStock = await prisma.storeStock.findMany({ where: { storeId: ahm.id, quantity: { gt: 20 } }, take: 3 });
  const done = await transfers.createTransfer(s1, {
    sourceType: 'STORE', fromStoreId: ahm.id, toStoreId: sur.id, notes: 'Surat running low (demo)',
    items: ahmStock.slice(0, 2).map((l) => ({ productId: l.productId, quantity: 5 })),
  });
  const mgrA = await contextFor(managerA.id);
  await transfers.approveTransfer(mgrA, done.id, {});
  await transfers.dispatchTransfer(s0, done.id);
  await transfers.receiveTransfer(s1, done.id, {});

  const approvedT = await transfers.createTransfer(s1, {
    sourceType: 'STORE', fromStoreId: ahm.id, toStoreId: sur.id,
    items: [{ productId: ahmStock[2].productId, quantity: 4 }],
  });
  await transfers.approveTransfer(mgrA, approvedT.id, {});
  const s2Stock = await prisma.storeStock.findFirstOrThrow({ where: { storeId: stores[2].id, quantity: { gt: 10 } } });
  await transfers.createTransfer(s3, { sourceType: 'STORE', fromStoreId: stores[2].id, toStoreId: stores[3].id, notes: 'Inter-region request (demo)', items: [{ productId: s2Stock.productId, quantity: 6 }] });
  const whT = await transfers.createTransfer(adminCtx, { sourceType: 'WAREHOUSE', fromWarehouseId: warehouse.id, toStoreId: stores[4].id, items: products.slice(45, 47).map((p) => ({ productId: p.id, quantity: 10 })) });
  await transfers.approveTransfer(adminCtx, whT.id, {});
  await transfers.dispatchTransfer(adminCtx, whT.id);

  const summary = {
    users: await prisma.user.count(),
    stores: await prisma.store.count(),
    categories: await prisma.category.count(),
    products: await prisma.product.count(),
    movements: await prisma.stockMovement.count(),
    requests: await prisma.productRequest.count(),
    packingOrders: await prisma.packingOrder.count(),
    transfers: await prisma.stockTransfer.count(),
    sales: saleCount,
    returns: await prisma.saleReturn.count(),
  };
  console.log('Seed complete:', summary);
  console.log('\nDevelopment credentials (DEV ONLY - change before sharing any environment):');
  console.log(`  Admin     ${adminEmail} / ${process.env.SEED_ADMIN_PASSWORD ? '<SEED_ADMIN_PASSWORD>' : adminPassword}`);
  console.log(`  Managers  manager.west@example.com, manager.metro@example.com / ${process.env.SEED_DEFAULT_PASSWORD ? '<SEED_DEFAULT_PASSWORD>' : defaultPassword}`);
  console.log(`  Stores    ahm.staff1@example.com … mum.staff4@example.com / same as managers`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
