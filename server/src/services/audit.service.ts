import { Prisma } from '@prisma/client';
import { Db } from '../utils/prisma';
import { RequestContext } from '../types/auth';
import { logger } from '../utils/logger';

export interface AuditEntry {
  action: string;
  module: string;
  recordId?: string | null;
  summary?: string;
  oldValue?: unknown;
  newValue?: unknown;
}

const SENSITIVE_KEYS = new Set(['passwordHash', 'password', 'tokenHash', 'tokenVersion', 'refreshToken']);

/** Strip secrets and make values JSON-safe (Decimal/Date -> string). */
function sanitize(value: unknown): Prisma.InputJsonValue | undefined {
  if (value === undefined || value === null) return undefined;
  return JSON.parse(
    JSON.stringify(value, (key, v) => (SENSITIVE_KEYS.has(key) ? undefined : v)),
  ) as Prisma.InputJsonValue;
}

/** Only keep the fields that actually changed, for compact old/new diffs. */
export function diff<T extends Record<string, unknown>>(before: T, after: Partial<T>) {
  const oldValue: Record<string, unknown> = {};
  const newValue: Record<string, unknown> = {};
  for (const key of Object.keys(after)) {
    const a = JSON.stringify(before[key] ?? null);
    const b = JSON.stringify(after[key] ?? null);
    if (a !== b) {
      oldValue[key] = before[key] ?? null;
      newValue[key] = after[key] ?? null;
    }
  }
  return { oldValue, newValue, changed: Object.keys(newValue).length > 0 };
}

/**
 * Writes an audit record. Pass the transaction client so the audit row commits
 * (or rolls back) together with the change it describes.
 */
export async function audit(db: Db, context: RequestContext | null, entry: AuditEntry) {
  try {
    await db.auditLog.create({
      data: {
        userId: context?.user.id ?? null,
        action: entry.action,
        module: entry.module,
        recordId: entry.recordId ?? null,
        summary: entry.summary?.slice(0, 500),
        oldValue: sanitize(entry.oldValue),
        newValue: sanitize(entry.newValue),
        ipAddress: context?.ip?.slice(0, 64),
        userAgent: context?.userAgent,
      },
    });
  } catch (err) {
    // Inside a transaction a failed insert aborts the transaction, so re-throw there.
    if ('$transaction' in db) {
      logger.error({ err, module: entry.module, action: entry.action }, 'Failed to write audit log');
      return;
    }
    throw err;
  }
}
