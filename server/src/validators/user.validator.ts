import { z } from 'zod';
import { MANAGER_ASSIGNABLE_PERMISSIONS } from '../config/permissions';
import { listQuery, nullableString, requiredString, uuid } from './common.validator';
import { passwordRule } from './auth.validator';

const email = z.string().trim().toLowerCase().pipe(z.email('Enter a valid email address'));
const role = z.enum(['ADMIN', 'MANAGER', 'STORE'], { message: 'Select a valid role' });
const permission = z.enum(MANAGER_ASSIGNABLE_PERMISSIONS as [string, ...string[]]);

export const userListQuery = listQuery.extend({
  role: z.preprocess((v) => (v === '' ? undefined : v), role.optional()),
});

export const createUserSchema = z
  .object({
    name: requiredString('Name', 100),
    email,
    phone: nullableString(20),
    password: passwordRule,
    role,
    storeId: uuid.nullable().optional(),
    permissions: z.array(permission).optional(),
    managedStoreIds: z.array(uuid).max(500).optional(),
  })
  .superRefine((v, ctx) => {
    if (v.role === 'STORE' && !v.storeId) {
      ctx.addIssue({ code: 'custom', path: ['storeId'], message: 'Store users must be assigned to a store' });
    }
  });

export const updateUserSchema = z.object({
  name: requiredString('Name', 100).optional(),
  email: email.optional(),
  phone: nullableString(20),
  storeId: uuid.nullable().optional(),
  status: z.enum(['ACTIVE', 'INACTIVE']).optional(),
  permissions: z.array(permission).optional(),
});

export const adminResetPasswordSchema = z.object({ newPassword: passwordRule });

export const managerStoresSchema = z.object({ storeIds: z.array(uuid).max(500) });
export const managerPermissionsSchema = z.object({ permissions: z.array(permission) });
