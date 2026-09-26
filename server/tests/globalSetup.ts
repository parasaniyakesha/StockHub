import { execSync } from 'node:child_process';

/**
 * Applies migrations to the dedicated test database once per run (non-destructive).
 * Each suite then truncates all tables and builds its own fixture (see helpers.resetDb).
 */
export default function setup() {
  const url = process.env.TEST_DATABASE_URL ?? 'postgresql://postgres@localhost:5433/stockhub_test?schema=public';
  if (!/test/i.test(new URL(url).pathname)) throw new Error('Refusing to use a database whose name does not contain "test"');
  execSync('npx prisma migrate deploy', {
    stdio: 'inherit',
    env: { ...process.env, DATABASE_URL: url, DIRECT_URL: url },
  });
}
