import { ApiError } from '../utils/apiError';
import { StoreScope } from '../types/auth';

/**
 * Store-level authorization helpers. Every query touching store-owned data must
 * pass through one of these so managers/store users can never read or write
 * data belonging to stores outside their scope.
 */

export function canAccessStore(scope: StoreScope, storeId: string | null | undefined): boolean {
  if (!storeId) return false;
  return scope.all || scope.storeIds.includes(storeId);
}

export function assertStoreAccess(scope: StoreScope, storeId: string | null | undefined) {
  if (!canAccessStore(scope, storeId)) throw ApiError.forbidden('You do not have access to this store');
}

/**
 * Resolves the effective store filter for list endpoints.
 * - If the client asks for a specific store it must be inside the scope (403 otherwise).
 * - Otherwise, restrict to the scope (undefined = no restriction, admins only).
 */
export function storeFilter(scope: StoreScope, requestedStoreId?: string): { in: string[] } | string | undefined {
  if (requestedStoreId) {
    assertStoreAccess(scope, requestedStoreId);
    return requestedStoreId;
  }
  return scope.all ? undefined : { in: scope.storeIds };
}

/** Used for single-record lookups: out-of-scope records are reported as not found. */
export function assertRecordInScope(scope: StoreScope, storeIds: (string | null | undefined)[], entity: string) {
  if (scope.all) return;
  if (!storeIds.some((id) => id && scope.storeIds.includes(id))) throw ApiError.notFound(entity);
}
