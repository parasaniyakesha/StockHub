import jwt, { SignOptions } from 'jsonwebtoken';
import { RecordStatus, Role } from '@prisma/client';
import { env } from '../config/env';
import { prisma } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { hashPassword, randomToken, sha256, verifyPassword } from '../utils/crypto';
import { toUserDto, userSelect } from '../models/user.model';
import { audit } from './audit.service';
import { mailConfigured, sendMail } from './mail.service';
import { RequestContext } from '../types/auth';

interface ClientInfo {
  ip?: string;
  userAgent?: string;
}

// Pre-computed hash so a login for an unknown email costs the same as a real one
// (prevents user enumeration through response timing).
let dummyHash: Promise<string> | null = null;
const getDummyHash = () => (dummyHash ??= hashPassword(randomToken(16)));

function signAccessToken(user: { id: string; role: Role; tokenVersion: number }) {
  return jwt.sign({ role: user.role, tv: user.tokenVersion }, env.JWT_ACCESS_SECRET, {
    subject: user.id,
    algorithm: 'HS256',
    issuer: 'stockhub',
    expiresIn: env.JWT_ACCESS_EXPIRES_IN as SignOptions['expiresIn'],
  });
}

async function issueRefreshToken(userId: string, client: ClientInfo) {
  const token = randomToken();
  const record = await prisma.refreshToken.create({
    data: {
      userId,
      tokenHash: sha256(token),
      expiresAt: new Date(Date.now() + env.REFRESH_TOKEN_TTL_DAYS * 86_400_000),
      userAgent: client.userAgent?.slice(0, 255),
      ipAddress: client.ip?.slice(0, 64),
    },
  });
  return { token, record };
}

async function loadUserDto(id: string) {
  const user = await prisma.user.findUniqueOrThrow({ where: { id }, select: userSelect });
  return toUserDto(user);
}

export async function login(email: string, password: string, client: ClientInfo) {
  const user = await prisma.user.findUnique({
    where: { email },
    select: { id: true, role: true, status: true, passwordHash: true, tokenVersion: true, storeId: true, store: { select: { status: true } } },
  });

  const valid = await verifyPassword(password, user?.passwordHash ?? (await getDummyHash()));
  if (!user || !valid) throw ApiError.unauthorized('Invalid email or password');
  if (user.status !== RecordStatus.ACTIVE) throw ApiError.forbidden('Your account is inactive. Contact your administrator.');
  if (user.role === Role.STORE && (!user.storeId || user.store?.status !== RecordStatus.ACTIVE)) {
    throw ApiError.forbidden('Your store is not active. Contact your administrator.');
  }

  const { token: refreshToken } = await issueRefreshToken(user.id, client);
  await prisma.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } });
  const dto = await loadUserDto(user.id);

  const context: RequestContext = {
    user: { id: dto.id, name: dto.name, email: dto.email, role: dto.role, storeId: dto.storeId, permissions: dto.permissions },
    scope: { all: false, storeIds: [] },
    ...client,
  };
  await audit(prisma, context, {
    action: 'LOGIN',
    module: 'auth',
    recordId: user.id,
    summary: `${dto.name} signed in`,
  });

  return { accessToken: signAccessToken(user), refreshToken, user: dto };
}

/**
 * Rotating refresh tokens: each refresh token is single-use. Presenting a token
 * that was already rotated indicates theft, so every session of that user is revoked.
 */
export async function refresh(refreshToken: string, client: ClientInfo) {
  const existing = await prisma.refreshToken.findUnique({
    where: { tokenHash: sha256(refreshToken) },
    include: { user: { select: { id: true, role: true, status: true, tokenVersion: true } } },
  });

  if (!existing) throw ApiError.unauthorized('Invalid session');

  if (existing.revokedAt) {
    await prisma.refreshToken.updateMany({
      where: { userId: existing.userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    throw ApiError.unauthorized('Session was revoked. Please sign in again.');
  }
  if (existing.expiresAt < new Date() || existing.user.status !== RecordStatus.ACTIVE) {
    throw ApiError.unauthorized('Session expired. Please sign in again.');
  }

  const { token, record } = await issueRefreshToken(existing.userId, client);
  // Conditional revoke guarantees only one concurrent refresh wins.
  const revoked = await prisma.refreshToken.updateMany({
    where: { id: existing.id, revokedAt: null },
    data: { revokedAt: new Date(), replacedBy: record.id },
  });
  if (!revoked.count) {
    await prisma.refreshToken.delete({ where: { id: record.id } });
    throw ApiError.unauthorized('Session was revoked. Please sign in again.');
  }

  return {
    accessToken: signAccessToken(existing.user),
    refreshToken: token,
    user: await loadUserDto(existing.userId),
  };
}

export async function logout(context: RequestContext, refreshToken?: string, allDevices = false) {
  if (allDevices) {
    await prisma.$transaction([
      prisma.refreshToken.updateMany({ where: { userId: context.user.id, revokedAt: null }, data: { revokedAt: new Date() } }),
      prisma.user.update({ where: { id: context.user.id }, data: { tokenVersion: { increment: 1 } } }),
    ]);
  } else if (refreshToken) {
    await prisma.refreshToken.updateMany({
      where: { tokenHash: sha256(refreshToken), userId: context.user.id, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }
  await audit(prisma, context, { action: 'LOGOUT', module: 'auth', recordId: context.user.id, summary: `${context.user.name} signed out` });
}

export const me = (userId: string) => loadUserDto(userId);

/**
 * Always resolves with the same generic outcome so the endpoint cannot be used to
 * discover which emails exist. The raw token is only returned outside production
 * when SMTP is not configured, to allow local testing of the reset flow.
 */
export async function forgotPassword(email: string) {
  const user = await prisma.user.findUnique({ where: { email }, select: { id: true, name: true, status: true } });
  if (!user || user.status !== RecordStatus.ACTIVE) return { devResetToken: undefined };

  const token = randomToken(32);
  await prisma.$transaction([
    prisma.passwordResetToken.updateMany({ where: { userId: user.id, usedAt: null }, data: { usedAt: new Date() } }),
    prisma.passwordResetToken.create({
      data: {
        userId: user.id,
        tokenHash: sha256(token),
        expiresAt: new Date(Date.now() + env.PASSWORD_RESET_TTL_MINUTES * 60_000),
      },
    }),
  ]);

  const link = env.APP_RESET_PASSWORD_URL ? `${env.APP_RESET_PASSWORD_URL}?token=${token}` : null;
  const sent = await sendMail(
    email,
    'StockHub password reset',
    `Hello ${user.name},\n\nUse this code to reset your StockHub password (valid for ${env.PASSWORD_RESET_TTL_MINUTES} minutes):\n\n${token}\n${
      link ? `\nOr open: ${link}\n` : ''
    }\nIf you did not request this, you can ignore this email.`,
  );

  return { devResetToken: !env.isProduction && !mailConfigured() && !sent ? token : undefined };
}

export async function resetPassword(token: string, newPassword: string) {
  const record = await prisma.passwordResetToken.findUnique({ where: { tokenHash: sha256(token) } });
  if (!record || record.usedAt || record.expiresAt < new Date()) {
    throw ApiError.badRequest('This reset code is invalid or has expired');
  }
  const passwordHash = await hashPassword(newPassword);
  await prisma.$transaction(async (tx) => {
    const used = await tx.passwordResetToken.updateMany({
      where: { id: record.id, usedAt: null },
      data: { usedAt: new Date() },
    });
    if (!used.count) throw ApiError.badRequest('This reset code is invalid or has expired');
    await tx.user.update({
      where: { id: record.userId },
      data: { passwordHash, tokenVersion: { increment: 1 } },
    });
    await tx.refreshToken.updateMany({ where: { userId: record.userId, revokedAt: null }, data: { revokedAt: new Date() } });
    await audit(tx, null, { action: 'PASSWORD_RESET', module: 'auth', recordId: record.userId, summary: 'Password reset via reset code' });
  });
}

export async function changePassword(context: RequestContext, currentPassword: string, newPassword: string) {
  const user = await prisma.user.findUniqueOrThrow({ where: { id: context.user.id }, select: { passwordHash: true } });
  if (!(await verifyPassword(currentPassword, user.passwordHash))) {
    throw ApiError.validation([{ field: 'currentPassword', message: 'Current password is incorrect' }]);
  }
  const passwordHash = await hashPassword(newPassword);
  await prisma.$transaction(async (tx) => {
    await tx.user.update({ where: { id: context.user.id }, data: { passwordHash, tokenVersion: { increment: 1 } } });
    await tx.refreshToken.updateMany({ where: { userId: context.user.id, revokedAt: null }, data: { revokedAt: new Date() } });
    await audit(tx, context, { action: 'PASSWORD_CHANGE', module: 'auth', recordId: context.user.id, summary: 'Changed own password' });
  });
}

export async function updateProfile(context: RequestContext, data: { name?: string; phone?: string | null }) {
  await prisma.user.update({ where: { id: context.user.id }, data });
  await audit(prisma, context, { action: 'UPDATE', module: 'auth', recordId: context.user.id, summary: 'Updated own profile', newValue: data });
  return loadUserDto(context.user.id);
}
