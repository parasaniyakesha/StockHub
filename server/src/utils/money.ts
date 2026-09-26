import { Prisma } from '@prisma/client';

export const D = (v: Prisma.Decimal.Value) => new Prisma.Decimal(v);

/** Round half-up to 2 decimal places (currency). */
export const round2 = (v: Prisma.Decimal) => v.toDecimalPlaces(2, Prisma.Decimal.ROUND_HALF_UP);

export const toNumber = (v: Prisma.Decimal | number | null | undefined) =>
  v === null || v === undefined ? 0 : typeof v === 'number' ? v : v.toNumber();
