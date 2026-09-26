import { z } from 'zod';
import {
  clientRequestId,
  listQuery,
  money,
  nonNegativeInt,
  nullableString,
  optionalString,
  positiveInt,
  requiredString,
  uniqueProducts,
  uuid,
} from './common.validator';

// ─────────────── Product requests ───────────────

const requestItems = z
  .array(z.object({ productId: uuid, requestedQuantity: positiveInt('Requested quantity'), notes: optionalString(300) }))
  .min(1, 'Add at least one product')
  .max(300)
  .superRefine(uniqueProducts);

export const createRequestSchema = z.object({
  storeId: uuid.optional(),
  notes: optionalString(1000),
  items: requestItems,
  submit: z.boolean().default(false),
  clientRequestId,
});

export const updateRequestSchema = z.object({
  notes: nullableString(1000),
  items: requestItems.optional(),
});

export const approveRequestSchema = z.object({
  reviewNotes: optionalString(1000),
  items: z
    .array(z.object({ itemId: uuid, approvedQuantity: nonNegativeInt('Approved quantity') }))
    .min(1)
    .max(300),
});

export const reasonSchema = z.object({ reason: requiredString('Reason', 1000) });
export const optionalReasonSchema = z.object({ reason: optionalString(1000) });

// ─────────────── Packing orders ───────────────

const packingStores = z
  .array(
    z.object({
      storeId: uuid,
      items: z
        .array(z.object({ productId: uuid, allocatedQuantity: nonNegativeInt('Allocated quantity') }))
        .max(300)
        .superRefine(uniqueProducts),
    }),
  )
  .min(1, 'Assign at least one store to this packing order')
  .max(200)
  .superRefine((stores, ctx) => {
    const seen = new Set<string>();
    stores.forEach((s, i) => {
      if (seen.has(s.storeId)) ctx.addIssue({ code: 'custom', path: [i, 'storeId'], message: 'Store is listed more than once' });
      seen.add(s.storeId);
    });
  });

export const createPackingOrderSchema = z.object({
  warehouseId: uuid.optional(),
  notes: optionalString(1000),
  items: z
    .array(z.object({ productId: uuid, quantity: positiveInt('Quantity') }))
    .min(1, 'Add at least one product')
    .max(300)
    .superRefine(uniqueProducts),
  stores: packingStores,
});

export const updatePackingOrderSchema = createPackingOrderSchema.partial();

export const packingFromRequestsSchema = z.object({
  requestIds: z.array(uuid).min(1, 'Select at least one approved request').max(100),
  warehouseId: uuid.optional(),
  notes: optionalString(1000),
});

export const packSchema = z.object({
  lines: z
    .array(z.object({ allocationId: uuid, packedQuantity: nonNegativeInt('Packed quantity') }))
    .max(5000)
    .optional(),
});

export const receiveLinesSchema = z.object({
  storeId: uuid.optional(),
  notes: optionalString(1000),
  lines: z
    .array(
      z.object({
        id: uuid,
        receivedQuantity: nonNegativeInt('Received quantity'),
        damagedQuantity: nonNegativeInt('Damaged quantity').default(0),
      }),
    )
    .max(1000)
    .optional(),
});

export const packingListQuery = listQuery;

// ─────────────── Transfers ───────────────

export const createTransferSchema = z
  .object({
    sourceType: z.enum(['WAREHOUSE', 'STORE']),
    fromStoreId: uuid.optional(),
    fromWarehouseId: uuid.optional(),
    toStoreId: uuid,
    notes: optionalString(1000),
    clientRequestId,
    items: z
      .array(z.object({ productId: uuid, quantity: positiveInt('Quantity') }))
      .min(1, 'Add at least one product')
      .max(300)
      .superRefine(uniqueProducts),
  })
  .superRefine((v, ctx) => {
    if (v.sourceType === 'STORE' && !v.fromStoreId) ctx.addIssue({ code: 'custom', path: ['fromStoreId'], message: 'Select the source store' });
    if (v.sourceType === 'STORE' && v.fromStoreId === v.toStoreId) {
      ctx.addIssue({ code: 'custom', path: ['toStoreId'], message: 'Source and destination must be different stores' });
    }
  });

export const approveTransferSchema = z.object({
  items: z.array(z.object({ itemId: uuid, approvedQuantity: nonNegativeInt('Approved quantity') })).max(300).optional(),
});

export const transferListQuery = listQuery.extend({
  direction: z.preprocess((v) => (v === '' ? undefined : v), z.enum(['IN', 'OUT']).optional()),
  sourceType: z.preprocess((v) => (v === '' ? undefined : v), z.enum(['WAREHOUSE', 'STORE']).optional()),
});

// ─────────────── Sales ───────────────

export const createSaleSchema = z.object({
  storeId: uuid.optional(),
  customerName: optionalString(120),
  customerPhone: z.preprocess(
    (v) => (v === '' ? undefined : v),
    z.string().trim().regex(/^[0-9+\-\s]{6,20}$/, 'Enter a valid phone number').optional(),
  ),
  paymentMethod: z.enum(['CASH', 'CARD', 'UPI', 'BANK_TRANSFER', 'CREDIT', 'OTHER']),
  discount: money('Discount').default(0),
  notes: optionalString(500),
  clientRequestId,
  items: z
    .array(
      z.object({
        productId: uuid,
        quantity: positiveInt('Quantity'),
        unitPrice: money('Unit price').optional(),
        discount: money('Line discount').default(0),
      }),
    )
    .min(1, 'Add at least one product')
    .max(200)
    .superRefine(uniqueProducts),
});

export const saleListQuery = listQuery.extend({
  paymentMethod: z.preprocess((v) => (v === '' ? undefined : v), z.enum(['CASH', 'CARD', 'UPI', 'BANK_TRANSFER', 'CREDIT', 'OTHER']).optional()),
});

// ─────────────── Returns ───────────────

export const createReturnSchema = z.object({
  storeId: uuid.optional(),
  saleId: uuid.optional(),
  notes: optionalString(1000),
  clientRequestId,
  items: z
    .array(
      z.object({
        productId: uuid,
        quantity: positiveInt('Quantity'),
        condition: z.enum(['GOOD', 'DAMAGED']),
        reason: requiredString('Reason', 300),
      }),
    )
    .min(1, 'Add at least one product')
    .max(200)
    .superRefine(uniqueProducts),
});

export const returnListQuery = listQuery.extend({
  condition: z.preprocess((v) => (v === '' ? undefined : v), z.enum(['GOOD', 'DAMAGED']).optional()),
});
