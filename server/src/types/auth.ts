import { Role } from '@prisma/client';
import { Permission } from '../config/permissions';

export interface AuthUser {
  id: string;
  name: string;
  email: string;
  role: Role;
  storeId: string | null;
  permissions: Permission[];
}

/**
 * Stores the authenticated user may access.
 * - ADMIN: all = true
 * - MANAGER: stores where assignedManagerId = user.id
 * - STORE: exactly the user's own store
 */
export interface StoreScope {
  all: boolean;
  storeIds: string[];
}

export interface RequestContext {
  user: AuthUser;
  scope: StoreScope;
  ip?: string;
  userAgent?: string;
}
