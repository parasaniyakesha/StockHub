import { Role, RecordStatus } from '@prisma/client';
import { effectivePermissions } from '../config/permissions';

/** Safe projection of a user - never includes passwordHash or tokenVersion. */
export const userSelect = {
  id: true,
  name: true,
  email: true,
  phone: true,
  role: true,
  status: true,
  storeId: true,
  permissions: true,
  lastLoginAt: true,
  createdAt: true,
  updatedAt: true,
  store: { select: { id: true, name: true, code: true } },
  managedStores: { select: { id: true, name: true, code: true }, orderBy: { name: 'asc' as const } },
} as const;

export interface UserRecord {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  role: Role;
  status: RecordStatus;
  storeId: string | null;
  permissions: string[];
  lastLoginAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
  store: { id: string; name: string; code: string } | null;
  managedStores: { id: string; name: string; code: string }[];
}

export function toUserDto(u: UserRecord) {
  return {
    id: u.id,
    name: u.name,
    email: u.email,
    phone: u.phone,
    role: u.role,
    status: u.status,
    storeId: u.storeId,
    store: u.store,
    managedStores: u.role === Role.MANAGER ? u.managedStores : [],
    // For managers this is the configured set; for others the fixed role set.
    permissions: effectivePermissions(u.role, u.permissions),
    lastLoginAt: u.lastLoginAt,
    createdAt: u.createdAt,
    updatedAt: u.updatedAt,
  };
}
