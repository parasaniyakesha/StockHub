import { z } from 'zod';
import { listQuery, optionalString, positiveInt, nonNegativeInt, requiredString, uniqueProducts, uuid } from './common.validator';

const movementTypes = ['OPENING', 'PURCHASE', 'TRANSFER_IN', 'TRANSFER_OUT', 'SALE', 'RETURN', 'DAMAGE', 'ADJUSTMENT', 'PACKING', 'CANCELLATION'] as const;

const location = z
  .object({
    locationType: z.enum(['WAREHOUSE', 'STORE']),
    storeId: uuid.optional(),
    warehouseId: uuid.optional(),
  })
  .superRefine((v, ctx) => {
    if (v.locationType === 'STORE' && !v.storeId) ctx.addIssue({ code: 'custom', path: ['storeId'], message: 'Select a store' });
  });

export const stockListQuery = listQuery.extend({
  locationType: z.enum(['WAREHOUSE', 'STORE']).default('STORE'),
  warehouseId: uuid.optional(),
  lowStock: z.coerce.boolean().optional(),
  hideZero: z.coerce.boolean().optional(),
});

export const movementListQuery = listQuery.extend({
  locationType: z.enum(['WAREHOUSE', 'STORE']).optional(),
  warehouseId: uuid.optional(),
  type: z.preprocess((v) => (v === '' ? undefined : v), z.enum(movementTypes).optional()),
  bucket: z.preprocess((v) => (v === '' ? undefined : v), z.enum(['AVAILABLE', 'DAMAGED']).optional()),
  referenceType: optionalString(40),
  referenceId: optionalString(64),
});

const positiveItems = z
  .array(z.object({ productId: uuid, quantity: positiveInt(), reason: optionalString(300) }))
  .min(1, 'Add at least one product')
  .max(500)
  .superRefine(uniqueProducts);

export const openingStockSchema = z.intersection(location, z.object({ items: positiveItems, reason: optionalString(300) }));

export const purchaseSchema = z.object({
  warehouseId: uuid.optional(),
  supplierReference: optionalString(80),
  reason: optionalString(300),
  items: positiveItems,
});

export const adjustmentSchema = z.intersection(
  location,
  z.object({
    reason: requiredString('Reason', 300),
    bucket: z.enum(['AVAILABLE', 'DAMAGED']).default('AVAILABLE'),
    items: z
      .array(
        z.object({
          productId: uuid,
          quantity: z.coerce
            .number()
            .int('Quantity must be a whole number')
            .refine((n) => n !== 0, 'Adjustment cannot be zero'),
        }),
      )
      .min(1, 'Add at least one product')
      .max(500)
      .superRefine(uniqueProducts),
  }),
);

export const damageSchema = z.intersection(
  location,
  z.object({
    items: z
      .array(z.object({ productId: uuid, quantity: positiveInt(), reason: requiredString('Reason', 300) }))
      .min(1, 'Add at least one product')
      .max(200)
      .superRefine(uniqueProducts),
  }),
);

export const writeOffSchema = damageSchema;

export const availabilitySchema = z.object({
  storeId: uuid.optional(),
  notes: optionalString(500),
  items: z
    .array(z.object({ productId: uuid, quantity: nonNegativeInt() }))
    .min(1, 'Add at least one product')
    .max(1000)
    .superRefine(uniqueProducts),
});

export const availabilityQuery = listQuery;

export const deleteBalanceQuery = z.object({ locationType: z.enum(['WAREHOUSE', 'STORE']) });
