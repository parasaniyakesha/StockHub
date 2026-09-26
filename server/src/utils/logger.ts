import pino from 'pino';
import { env } from '../config/env';

// Sensitive values are redacted so they never reach log storage.
export const logger = pino({
  level: env.isTest ? 'silent' : env.LOG_LEVEL,
  redact: {
    paths: [
      'req.headers.authorization',
      'req.headers.cookie',
      'password',
      'newPassword',
      'currentPassword',
      'passwordHash',
      'refreshToken',
      'accessToken',
      'token',
      '*.password',
      '*.passwordHash',
      '*.refreshToken',
      '*.token',
    ],
    censor: '[REDACTED]',
  },
  base: undefined,
  timestamp: pino.stdTimeFunctions.isoTime,
});
