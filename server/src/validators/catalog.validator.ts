import { z } from 'zod';
import { listQuery, money, nonNegativeInt, nullableString, optionalString, requiredString, uuid } from './common.validator';

const code = (label: string) =>
  z
    .string({ message: `${label} is required` })
    .trim()
    .min(2, `${label} must be at least 2 characters`)
    .max(30)
    .regex(/^[A-Za-z0-9_-]+$/, `${label} may only contain letters, numbers, - and _`)
    .transform((v) => v.toUpperCase());

// ─────────────── Stores ───────────────

const storeFields = {
  name: requiredString('Store name', 120),
  code: code('Store code'),
  address: nullableString(300),
  city: nullableString(80),
  phone: nullableString(20),
  email: z.preprocess((v) => (v === '' ? null : v), z.email('Enter a valid email').nullable().optional()),
  contactPerson: nullableString(100),
  assignedManagerId: uuid.nullable().optional(),
};

export const createStoreSchema = z.object(storeFields);
export const updateStoreSchema = z.object(storeFields).partial();
export const storeListQuery = listQuery.extend({ city: optionalString(80) });
export const assignManagerSchema = z.object({ managerId: uuid.nullable() });
export const assignStoreUsersSchema = z.object({ userIds: z.array(uuid).min(1).max(200) });

// ─────────────── Categories ───────────────

const categoryFields = {
  name: requiredString('Category name', 100),
  code: code('Category code'),
  description: nullableString(500),
  parentId: uuid.nullable().optional(),
};

export const createCategorySchema = z.object(categoryFields);
export const updateCategorySchema = z.object(categoryFields).partial();
export const categoryListQuery = listQuery.extend({
  parentId: z.preprocess((v) => (v === '' ? undefined : v), z.union([uuid, z.literal('root')]).optional()),
  all: z.coerce.boolean().optional(),
});
export const assignProductsSchema = z.object({ productIds: z.array(uuid).min(1).max(500) });

// ─────────────── Products ───────────────

const productBase = z.object({
  name: requiredString('Product name', 150),
  sku: code('SKU'),
  barcode: z.preprocess(
    (v) => (v === '' ? null : v),
    z.string().trim().max(64).regex(/^[A-Za-z0-9-]+$/, 'Barcode may only contain letters, numbers and -').nullable().optional(),
  ),
  categoryId: uuid,
  brand: nullableString(80),
  unit: z.string().trim().min(1).max(20).default('PCS'),
  description: nullableString(2000),
  purchasePrice: money('Purchase price'),
  sellingPrice: money('Selling price'),
  taxRate: z.coerce.number().min(0, 'Tax rate cannot be negative').max(100, 'Tax rate cannot exceed 100').default(0),
  minimumStock: nonNegativeInt('Minimum stock').default(0),
  maximumStock: z.preprocess((v) => (v === '' ? null : v), nonNegativeInt('Maximum stock').nullable().optional()),
  imageUrl: z.preprocess((v) => (v === '' ? null : v), z.url('Enter a valid image URL').max(1000).nullable().optional()),
});

const stockRange = (v: { minimumStock?: number; maximumStock?: number | null }, ctx: z.RefinementCtx) => {
  if (v.maximumStock != null && v.minimumStock != null && v.maximumStock < v.minimumStock) {
    ctx.addIssue({ code: 'custom', path: ['maximumStock'], message: 'Maximum stock must be greater than minimum stock' });
  }
};

export const createProductSchema = productBase.superRefine(stockRange);
export const updateProductSchema = productBase.partial().superRefine(stockRange);

export const productListQuery = listQuery.extend({
  lowStock: z.coerce.boolean().optional(),
  brand: optionalString(80),
});

export const importProductsSchema = z.object({
  rows: z
    .array(
      z.object({
        name: z.unknown(),
        sku: z.unknown(),
        barcode: z.unknown().optional(),
        categoryCode: z.unknown(),
        brand: z.unknown().optional(),
        unit: z.unknown().optional(),
        description: z.unknown().optional(),
        purchasePrice: z.unknown(),
        sellingPrice: z.unknown(),
        taxRate: z.unknown().optional(),
        minimumStock: z.unknown().optional(),
        maximumStock: z.unknown().optional(),
        imageUrl: z.unknown().optional(),
      }),
    )
    .min(1, 'The file has no rows')
    .max(2000, 'Import at most 2000 rows at a time'),
});

export const exportQuery = z.object({ format: z.enum(['csv', 'xlsx', 'pdf']).default('csv') });

// ─────────────── Warehouses ───────────────

export const warehouseSchema = z.object({
  name: requiredString('Warehouse name', 120),
  code: code('Warehouse code'),
  address: nullableString(300),
  isDefault: z.boolean().optional(),
});
