import { RecordStatus } from '@prisma/client';
import { z } from 'zod';
import { Db, prisma } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { RequestContext } from '../types/auth';
import { audit } from './audit.service';
import { warehouseSchema } from '../validators/catalog.validator';

export async function getDefaultWarehouse(db: Db = prisma) {
  const warehouse =
    (await db.warehouse.findFirst({ where: { isDefault: true, status: RecordStatus.ACTIVE } })) ??
    (await db.warehouse.findFirst({ where: { status: RecordStatus.ACTIVE }, orderBy: { createdAt: 'asc' } }));
  if (!warehouse) throw ApiError.invalidState('No active central warehouse is configured');
  return warehouse;
}

export async function resolveWarehouse(db: Db, warehouseId?: string) {
  if (!warehouseId) return getDefaultWarehouse(db);
  const warehouse = await db.warehouse.findUnique({ where: { id: warehouseId } });
  if (!warehouse || warehouse.status !== RecordStatus.ACTIVE) {
    throw ApiError.validation([{ field: 'warehouseId', message: 'Warehouse does not exist or is inactive' }]);
  }
  return warehouse;
}

export const listWarehouses = () => prisma.warehouse.findMany({ orderBy: [{ isDefault: 'desc' }, { name: 'asc' }] });

export async function createWarehouse(context: RequestContext, input: z.infer<typeof warehouseSchema>) {
  return prisma.$transaction(async (tx) => {
    if (input.isDefault) await tx.warehouse.updateMany({ data: { isDefault: false } });
    const warehouse = await tx.warehouse.create({ data: input });
    await audit(tx, context, { action: 'CREATE', module: 'warehouses', recordId: warehouse.id, summary: `Created warehouse ${warehouse.name}`, newValue: warehouse });
    return warehouse;
  });
}

export async function updateWarehouse(context: RequestContext, id: string, input: Partial<z.infer<typeof warehouseSchema>> & { status?: RecordStatus }) {
  const existing = await prisma.warehouse.findUnique({ where: { id } });
  if (!existing) throw ApiError.notFound('Warehouse');
  return prisma.$transaction(async (tx) => {
    if (input.isDefault) await tx.warehouse.updateMany({ where: { id: { not: id } }, data: { isDefault: false } });
    const warehouse = await tx.warehouse.update({ where: { id }, data: input });
    await audit(tx, context, { action: 'UPDATE', module: 'warehouses', recordId: id, summary: `Updated warehouse ${warehouse.name}`, oldValue: existing, newValue: warehouse });
    return warehouse;
  });
}
