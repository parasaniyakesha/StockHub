import { z } from 'zod';

export const uuid = z.uuid({ message: 'Invalid identifier' });
export const idParam = z.object({ id: uuid });

const emptyToUndefined = (v: unknown) => (v === '' || v === null ? undefined : v);

export const optionalString = (max = 255) =>
  z.preprocess(emptyToUndefined, z.string().trim().max(max).optional());

export const nullableString = (max = 255) =>
  z.preprocess((v) => (v === '' ? null : v), z.string().trim().max(max).nullable().optional());

export const requiredString = (label: string, max = 255) =>
  z.string({ message: `${label} is required` }).trim().min(1, `${label} is required`).max(max);

export const positiveInt = (label = 'Quantity') =>
  z.coerce.number({ message: `${label} must be a number` }).int(`${label} must be a whole number`).positive(`${label} must be greater than 0`);

export const nonNegativeInt = (label = 'Quantity') =>
  z.coerce.number({ message: `${label} must be a number` }).int(`${label} must be a whole number`).min(0, `${label} cannot be negative`);

export const money = (label = 'Amount') =>
  z.coerce.number({ message: `${label} must be a number` }).min(0, `${label} cannot be negative`).max(9_999_999_999, `${label} is too large`);

export const optionalDate = z.preprocess(emptyToUndefined, z.coerce.date({ message: 'Invalid date' }).optional());

/** Standard list query: ?page&limit&search&status&storeId&categoryId&startDate&endDate&sortBy&sortOrder */
export const listQuery = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(200).default(20),
  search: optionalString(100),
  status: optionalString(40),
  storeId: z.preprocess(emptyToUndefined, uuid.optional()),
  categoryId: z.preprocess(emptyToUndefined, uuid.optional()),
  productId: z.preprocess(emptyToUndefined, uuid.optional()),
  managerId: z.preprocess(emptyToUndefined, uuid.optional()),
  startDate: optionalDate,
  endDate: optionalDate,
  sortBy: optionalString(40),
  sortOrder: z.preprocess(emptyToUndefined, z.enum(['asc', 'desc']).optional()),
});

export type ListQuery = z.infer<typeof listQuery>;

export const statusBody = z.object({ status: z.enum(['ACTIVE', 'INACTIVE']) });

export const clientRequestId = z.preprocess(emptyToUndefined, z.string().trim().min(8).max(64).optional());

/** Rejects duplicate productIds inside an items array. */
export function uniqueProducts<T extends { productId: string }>(items: T[], ctx: z.RefinementCtx) {
  const seen = new Set<string>();
  items.forEach((item, i) => {
    if (seen.has(item.productId)) {
      ctx.addIssue({ code: 'custom', path: [i, 'productId'], message: 'Product is listed more than once' });
    }
    seen.add(item.productId);
  });
}
