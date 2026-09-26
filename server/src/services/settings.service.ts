import { Prisma } from '@prisma/client';
import { Db, prisma } from '../utils/prisma';
import { audit } from './audit.service';
import { RequestContext } from '../types/auth';

export interface AppSettings {
  companyName: string;
  currencyCode: string;
  currencySymbol: string;
  /** When false (default), no operation may drive available stock below zero. */
  allowNegativeStock: boolean;
  lowStockAlerts: boolean;
  /** Store users may override the catalog selling price on a sale line. */
  allowPriceOverride: boolean;
  invoicePrefix: string;
  timezone: string;
}

export const DEFAULT_SETTINGS: AppSettings = {
  companyName: 'StockHub Demo Company',
  currencyCode: 'INR',
  currencySymbol: '₹',
  allowNegativeStock: false,
  lowStockAlerts: true,
  allowPriceOverride: false,
  invoicePrefix: 'INV',
  timezone: 'Asia/Kolkata',
};

export async function getSettings(db: Db = prisma): Promise<AppSettings> {
  const rows = await db.setting.findMany();
  const stored = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  return { ...DEFAULT_SETTINGS, ...stored } as AppSettings;
}

export async function updateSettings(context: RequestContext, patch: Partial<AppSettings>) {
  return prisma.$transaction(async (tx) => {
    const before = await getSettings(tx);
    for (const [key, value] of Object.entries(patch)) {
      if (value === undefined) continue;
      await tx.setting.upsert({
        where: { key },
        create: { key, value: value as Prisma.InputJsonValue },
        update: { value: value as Prisma.InputJsonValue },
      });
    }
    const after = await getSettings(tx);
    await audit(tx, context, {
      action: 'UPDATE',
      module: 'settings',
      summary: 'Updated application settings',
      oldValue: before,
      newValue: after,
    });
    return after;
  });
}
