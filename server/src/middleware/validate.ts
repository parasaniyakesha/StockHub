import { NextFunction, Request, Response } from 'express';
import { z, ZodType } from 'zod';
import { ApiError } from '../utils/apiError';

interface Schemas {
  body?: ZodType;
  query?: ZodType;
  params?: ZodType;
}

export function toFieldErrors(error: z.ZodError) {
  return error.issues.map((issue) => ({
    field: issue.path.join('.') || 'input',
    message: issue.message,
  }));
}

/**
 * Validates body / query / params. Parsed (coerced, stripped) values are placed
 * on req.validated - controllers must read from there, never the raw request.
 */
export const validate = (schemas: Schemas) => (req: Request, _res: Response, next: NextFunction) => {
  const validated: NonNullable<Request['validated']> = {};
  for (const key of ['params', 'query', 'body'] as const) {
    const schema = schemas[key];
    if (!schema) continue;
    const result = schema.safeParse(req[key] ?? {});
    if (!result.success) return next(ApiError.validation(toFieldErrors(result.error)));
    validated[key] = result.data;
  }
  req.validated = validated;
  next();
};
