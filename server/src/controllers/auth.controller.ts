import { Request, Response } from 'express';
import * as auth from '../services/auth.service';
import { ctx } from '../middleware/authorize';
import { ok } from '../utils/response';

const client = (req: Request) => ({ ip: req.ip, userAgent: req.get('user-agent') });

export async function login(req: Request, res: Response) {
  const { email, password } = req.validated!.body;
  ok(res, await auth.login(email, password, client(req)), 'Signed in successfully');
}

export async function refresh(req: Request, res: Response) {
  ok(res, await auth.refresh(req.validated!.body.refreshToken, client(req)), 'Session refreshed');
}

export async function logout(req: Request, res: Response) {
  const { refreshToken, allDevices } = req.validated!.body;
  await auth.logout(ctx(req), refreshToken, allDevices);
  ok(res, null, 'Signed out');
}

export async function me(req: Request, res: Response) {
  ok(res, await auth.me(ctx(req).user.id), 'Current user');
}

export async function forgotPassword(req: Request, res: Response) {
  const result = await auth.forgotPassword(req.validated!.body.email);
  ok(res, result.devResetToken ? { devResetToken: result.devResetToken } : null,
    'If an account exists for this email, a reset code has been sent.');
}

export async function resetPassword(req: Request, res: Response) {
  const { token, newPassword } = req.validated!.body;
  await auth.resetPassword(token, newPassword);
  ok(res, null, 'Password has been reset. Please sign in.');
}

export async function changePassword(req: Request, res: Response) {
  const { currentPassword, newPassword } = req.validated!.body;
  await auth.changePassword(ctx(req), currentPassword, newPassword);
  ok(res, null, 'Password changed. Please sign in again.');
}

export async function updateProfile(req: Request, res: Response) {
  ok(res, await auth.updateProfile(ctx(req), req.validated!.body), 'Profile updated');
}
