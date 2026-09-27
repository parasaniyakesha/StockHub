import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import pinoHttp from 'pino-http';
import { env } from './config/env';
import { logger } from './utils/logger';
import { apiLimiter } from './middleware/rateLimit';
import { errorHandler, notFoundHandler } from './middleware/errorHandler';
import routes from './routes';

// Raw SQL aggregates return BigInt; make them JSON-serialisable.
(BigInt.prototype as unknown as { toJSON: () => number }).toJSON = function toJSON(this: bigint) {
  return Number(this);
};

export function createApp() {
  const app = express();

  app.disable('x-powered-by');
  if (env.TRUST_PROXY > 0 || env.isProduction || process.env.RENDER) {
    app.set('trust proxy', env.TRUST_PROXY > 0 ? env.TRUST_PROXY : 1);
  }

  app.use(helmet());
  app.use(
    cors({
      // Desktop clients send no Origin header and are always allowed.
      origin(origin, callback) {
        if (!origin || env.corsOrigins.includes(origin) || (!env.isProduction && /^http:\/\/localhost(:\d+)?$/.test(origin))) {
          return callback(null, true);
        }
        return callback(null, false);
      },
      exposedHeaders: ['Content-Disposition'],
      maxAge: 600,
    }),
  );
  app.use(express.json({ limit: '2mb' }));
  app.use(
    pinoHttp({
      logger,
      autoLogging: { ignore: (req) => req.url === '/api/health' },
      customLogLevel: (_req, res, err) => (err || res.statusCode >= 500 ? 'error' : res.statusCode >= 400 ? 'warn' : 'info'),
      serializers: {
        req: (req) => ({ method: req.method, url: req.url }),
        res: (res) => ({ statusCode: res.statusCode }),
      },
    }),
  );

  app.use('/api', apiLimiter, routes);
  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}

export default createApp();
