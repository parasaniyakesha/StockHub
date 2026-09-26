import { NextFunction, Request, Response } from 'express';
import { Role } from '@prisma/client';
import { Permission } from '../config/permissions';
import { ApiError } from '../utils/apiError';
import { RequestContext } from '../types/auth';

/** Returns the request context. Only valid after authenticate(). */
export function ctx(req: Request): RequestContext {
  if (!req.ctx) throw ApiError.unauthorized();
  return req.ctx;
}

export const requireRole =
  (...roles: Role[]) =>
  (req: Request, _res: Response, next: NextFunction) => {
    const user = req.ctx?.user;
    if (!user) return next(ApiError.unauthorized());
    if (!roles.includes(user.role)) return next(ApiError.forbidden());
    next();
  };

/** Passes when the user holds ANY of the listed permissions. */
export const requirePermission =
  (...permissions: Permission[]) =>
  (req: Request, _res: Response, next: NextFunction) => {
    const user = req.ctx?.user;
    if (!user) return next(ApiError.unauthorized());
    if (!permissions.some((p) => user.permissions.includes(p))) return next(ApiError.forbidden());
    next();
  };

export function hasPermission(context: RequestContext, permission: Permission) {
  return context.user.permissions.includes(permission);
}

export function assertPermission(context: RequestContext, permission: Permission) {
  if (!hasPermission(context, permission)) throw ApiError.forbidden();
}
