import { Db } from './prisma';

/**
 * Returns the next value of a named sequence atomically (single UPSERT ... RETURNING),
 * so two concurrent transactions can never receive the same document number.
 */
export async function nextSequence(db: Db, key: string, start = 1000): Promise<number> {
  const rows = await db.$queryRaw<{ value: number }[]>`
    INSERT INTO counters ("key", "value") VALUES (${key}, ${start + 1})
    ON CONFLICT ("key") DO UPDATE SET "value" = counters."value" + 1
    RETURNING "value"`;
  return Number(rows[0].value);
}

export async function nextDocumentNumber(db: Db, prefix: string): Promise<string> {
  const n = await nextSequence(db, prefix);
  return `${prefix}-${n}`;
}
