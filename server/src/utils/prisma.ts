import { Prisma, PrismaClient } from '@prisma/client';
import { env } from '../config/env';

// Re-use a single client across hot reloads / serverless invocations.
const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

export const prisma =
  globalForPrisma.prisma ??
  new PrismaClient({
    // Prisma's own error log echoes query arguments; unexpected errors are logged
    // (redacted) by the error handler instead, so keep Prisma quiet outside development.
    log: env.isProduction || env.isTest ? ['warn'] : ['warn', 'error'],
  });

if (!env.isProduction) globalForPrisma.prisma = prisma;

export type Tx = Prisma.TransactionClient;
export type Db = PrismaClient | Tx;

/**
 * Runs `fn` inside a serializable-safe interactive transaction. Stock operations
 * additionally use conditional updates (see stockLedger) so concurrent requests
 * cannot drive balances negative.
 */
export function transaction<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
  return prisma.$transaction(fn, {
    maxWait: 10_000,
    timeout: 30_000,
  });
}
