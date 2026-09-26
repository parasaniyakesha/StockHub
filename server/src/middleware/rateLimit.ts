import rateLimit from 'express-rate-limit';
import { env } from '../config/env';

const handler = (_req: unknown, res: { status: (n: number) => { json: (b: unknown) => void } }) =>
  res.status(429).json({ success: false, message: 'Too many requests. Please try again later.', code: 'RATE_LIMITED' });

// Note: the default memory store is per-instance. On serverless / multi-instance
// deployments plug a shared store (e.g. Redis/Upstash) in here.
export const apiLimiter = rateLimit({
  windowMs: env.RATE_LIMIT_WINDOW_MINUTES * 60_000,
  limit: env.RATE_LIMIT_MAX,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skip: () => env.isTest,
  handler,
});

export const authLimiter = rateLimit({
  windowMs: env.RATE_LIMIT_WINDOW_MINUTES * 60_000,
  limit: env.AUTH_RATE_LIMIT_MAX,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skipSuccessfulRequests: true,
  skip: () => env.isTest,
  handler,
});
