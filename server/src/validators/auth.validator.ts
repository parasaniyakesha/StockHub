import { z } from 'zod';

export const passwordRule = z
  .string({ message: 'Password is required' })
  .min(8, 'Password must be at least 8 characters')
  .max(72, 'Password must be at most 72 characters')
  .regex(/[a-z]/, 'Password must contain a lowercase letter')
  .regex(/[A-Z]/, 'Password must contain an uppercase letter')
  .regex(/[0-9]/, 'Password must contain a number');

const email = z.string({ message: 'Email is required' }).trim().toLowerCase().pipe(z.email('Enter a valid email address'));

export const loginSchema = z.object({
  email,
  password: z.string({ message: 'Password is required' }).min(1, 'Password is required').max(200),
});

export const refreshSchema = z.object({
  refreshToken: z.string({ message: 'Refresh token is required' }).min(20).max(200),
});

export const logoutSchema = z.object({
  refreshToken: z.string().min(20).max(200).optional(),
  allDevices: z.boolean().optional(),
});

export const forgotPasswordSchema = z.object({ email });

export const resetPasswordSchema = z.object({
  token: z.string({ message: 'Reset token is required' }).min(20).max(200),
  newPassword: passwordRule,
});

export const changePasswordSchema = z.object({
  currentPassword: z.string().min(1, 'Current password is required'),
  newPassword: passwordRule,
});

export const updateProfileSchema = z.object({
  name: z.string().trim().min(2, 'Name is required').max(100).optional(),
  phone: z.string().trim().max(20).nullable().optional(),
});
