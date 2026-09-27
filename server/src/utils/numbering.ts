import { Db } from './prisma';

/**
 * Returns the next value of a named sequence atomically (single UPSERT ... RETURNING),
 * so two concurrent transactions can never receive the same document number.
 */
export async function nextSequence(db: Db, key: string, start = 1000): Promise<number> {
  const counter = await db.counter.upsert({
    where: { key },
    update: { value: { increment: 1 } },
    create: { key, value: start + 1 },
  });
  return counter.value;
}

export async function nextDocumentNumber(db: Db, prefix: string): Promise<string> {
  const n = await nextSequence(db, prefix);
  return `${prefix}-${n}`;
}
