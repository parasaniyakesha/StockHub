import { NextFunction, Request, Response } from 'express';
import { Prisma } from '@prisma/client';
import { ZodError } from 'zod';
import { ApiError } from '../utils/apiError';
import { logger } from '../utils/logger';
import { toFieldErrors } from './validate';

export function notFoundHandler(req: Request, _res: Response, next: NextFunction) {
  next(new ApiError(404, 'NOT_FOUND', `Route ${req.method} ${req.path} not found`));
}

/**
 * Converts every error into the standard `{ success:false, message, code }` shape.
 * Internal details (stack traces, SQL, Prisma messages) are logged, never returned.
 */
// eslint-disable-next-line @typescript-eslint/no-unused-vars
export function errorHandler(err: unknown, req: Request, res: Response, _next: NextFunction) {
  let apiError: ApiError;

  if (err instanceof ApiError) {
    apiError = err;
  } else if (err instanceof ZodError) {
    apiError = ApiError.validation(toFieldErrors(err));
  } else if (err instanceof Prisma.PrismaClientKnownRequestError) {
    apiError = mapPrismaError(err);
  } else if (isBodyParserError(err)) {
    apiError = ApiError.badRequest('Malformed request body');
  } else {
    apiError = new ApiError(500, 'INTERNAL_ERROR', 'Something went wrong. Please try again.');
  }

  if (apiError.statusCode >= 500) {
    logger.error({ err, path: req.path, method: req.method, userId: req.ctx?.user.id }, 'Unhandled error');
  }

  res.status(apiError.statusCode).json({
    success: false,
    message: apiError.message,
    code: apiError.code,
    ...(apiError.errors ? { errors: apiError.errors } : {}),
  });
}

function mapPrismaError(err: Prisma.PrismaClientKnownRequestError): ApiError {
  switch (err.code) {
    case 'P2002': {
      const target = (err.meta?.target as string[] | string | undefined) ?? [];
      const fields = Array.isArray(target) ? target : [target];
      if (fields.includes('clientRequestId')) {
        return ApiError.conflict('This transaction was already submitted');
      }
      return new ApiError(409, 'CONFLICT', `A record with this ${fields.join(', ') || 'value'} already exists`,
        fields.map((f) => ({ field: f, message: 'Already exists' })));
    }
    case 'P2025':
      return ApiError.notFound();
    case 'P2003':
      return ApiError.badRequest('Referenced record does not exist or is still in use');
    case 'P2034':
      return ApiError.conflict('The record was modified concurrently. Please retry.');
    default:
      return new ApiError(500, 'INTERNAL_ERROR', 'Something went wrong. Please try again.');
  }
}

function isBodyParserError(err: unknown): boolean {
  return typeof err === 'object' && err !== null && 'type' in err && (err as { type: string }).type === 'entity.parse.failed';
}
