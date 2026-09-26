import app from './src/app';
import { env } from './src/config/env';
import { logger } from './src/utils/logger';
import { prisma } from './src/utils/prisma';

const server = app.listen(env.PORT, () => {
  logger.info(`StockHub API listening on http://localhost:${env.PORT}/api (${env.NODE_ENV})`);
});

async function shutdown(signal: string) {
  logger.info(`${signal} received, shutting down`);
  server.close(async () => {
    await prisma.$disconnect();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('SIGTERM', () => void shutdown('SIGTERM'));
