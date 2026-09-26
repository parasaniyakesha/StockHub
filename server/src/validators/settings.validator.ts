import { z } from 'zod';
import { listQuery, optionalString, uuid } from './common.validator';

export const updateSettingsSchema = z
  .object({
    companyName: z.string().trim().min(2).max(120),
    currencyCode: z.string().trim().length(3).transform((v) => v.toUpperCase()),
    currencySymbol: z.string().trim().min(1).max(5),
    allowNegativeStock: z.boolean(),
    lowStockAlerts: z.boolean(),
    allowPriceOverride: z.boolean(),
    invoicePrefix: z.string().trim().min(1).max(10).regex(/^[A-Z0-9]+$/i, 'Letters and numbers only').transform((v) => v.toUpperCase()),
    timezone: z.string().trim().refine((tz) => {
      try {
        new Intl.DateTimeFormat('en-US', { timeZone: tz });
        return true;
      } catch {
        return false;
      }
    }, 'Unknown timezone'),
  })
  .partial()
  .strict();

export const notificationListQuery = listQuery.extend({ unreadOnly: z.coerce.boolean().optional() });

export const dashboardQuery = z.object({ storeId: z.preprocess((v) => (v === '' ? undefined : v), uuid.optional()) });

export const exportFormatQuery = z.object({ format: z.enum(['csv', 'xlsx', 'pdf']).default('csv') });

export { optionalString };
