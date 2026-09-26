import { NextFunction, Request, Response } from 'express';
import jwt, { TokenExpiredError } from 'jsonwebtoken';
import { RecordStatus, Role } from '@prisma/client';
import { env } from '../config/env';
import { effectivePermissions } from '../config/permissions';
import { ApiError } from '../utils/apiError';
import { prisma } from '../utils/prisma';
import { StoreScope } from '../types/auth';

export interface AccessTokenPayload {
  sub: string;
  role: Role;
  tv: number;
}

/**
 * Verifies the bearer access token and re-loads the user from the database on
 * every request, so deactivation, role changes, store re-assignment and
 * password changes take effect immediately (not only when the token expires).
 */
export async function authenticate(req: Request, _res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) return next(ApiError.unauthorized());

  let payload: AccessTokenPayload;
  try {
    payload = jwt.verify(header.slice(7), env.JWT_ACCESS_SECRET, {
      algorithms: ['HS256'],
      issuer: 'stockhub',
    }) as unknown as AccessTokenPayload;
  } catch (err) {
    if (err instanceof TokenExpiredError) {
      return next(new ApiError(401, 'TOKEN_EXPIRED', 'Session expired'));
    }
    return next(ApiError.unauthorized('Invalid session'));
  }

  const user = await prisma.user.findUnique({
    where: { id: payload.sub },
    select: {
      id: true,
      name: true,
      email: true,
      role: true,
      status: true,
      storeId: true,
      permissions: true,
      tokenVersion: true,
      store: { select: { status: true } },
    },
  });

  if (!user || user.status !== RecordStatus.ACTIVE || user.tokenVersion !== payload.tv) {
    return next(ApiError.unauthorized('Invalid session'));
  }
  if (user.role === Role.STORE && (!user.storeId || user.store?.status !== RecordStatus.ACTIVE)) {
    return next(ApiError.forbidden('Your store is not active'));
  }

  req.ctx = {
    user: {
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role,
      storeId: user.storeId,
      permissions: effectivePermissions(user.role, user.permissions),
    },
    scope: await resolveScope(user.id, user.role, user.storeId),
    ip: req.ip,
    userAgent: req.get('user-agent')?.slice(0, 255),
  };
  next();
}

export async function resolveScope(userId: string, role: Role, storeId: string | null): Promise<StoreScope> {
  if (role === Role.ADMIN) return { all: true, storeIds: [] };
  if (role === Role.STORE) return { all: false, storeIds: storeId ? [storeId] : [] };
  const stores = await prisma.store.findMany({
    where: { assignedManagerId: userId },
    select: { id: true },
  });
  return { all: false, storeIds: stores.map((s) => s.id) };
}
