import { RecordStatus, Role } from '@prisma/client';
import { Db, prisma } from '../utils/prisma';
import { ApiError } from '../utils/apiError';
import { ListQuery } from '../validators/common.validator';
import { pageArgs } from '../utils/pagination';

export const NotificationType = {
  REQUEST_SUBMITTED: 'REQUEST_SUBMITTED',
  REQUEST_APPROVED: 'REQUEST_APPROVED',
  REQUEST_REJECTED: 'REQUEST_REJECTED',
  PACKING_CREATED: 'PACKING_CREATED',
  PACKING_DISPATCHED: 'PACKING_DISPATCHED',
  STOCK_RECEIVED: 'STOCK_RECEIVED',
  TRANSFER_REQUESTED: 'TRANSFER_REQUESTED',
  TRANSFER_APPROVED: 'TRANSFER_APPROVED',
  TRANSFER_REJECTED: 'TRANSFER_REJECTED',
  TRANSFER_DISPATCHED: 'TRANSFER_DISPATCHED',
  TRANSFER_RECEIVED: 'TRANSFER_RECEIVED',
  LOW_STOCK: 'LOW_STOCK',
  RETURN_RECORDED: 'RETURN_RECORDED',
  DAMAGE_REPORTED: 'DAMAGE_REPORTED',
} as const;

export interface NotifyInput {
  type: string;
  title: string;
  message: string;
  entityType?: string;
  entityId?: string;
  /** Deliver to all active admins. */
  admins?: boolean;
  /** Deliver to the assigned managers and store users of these stores. */
  storeIds?: string[];
  /** Only managers of storeIds (not store users). */
  managersOnly?: boolean;
  userIds?: string[];
  excludeUserId?: string;
}

/** Fan-out a notification to every relevant recipient. */
export async function notify(db: Db, input: NotifyInput) {
  const recipients = new Set<string>(input.userIds ?? []);

  if (input.admins) {
    const admins = await db.user.findMany({
      where: { role: Role.ADMIN, status: RecordStatus.ACTIVE },
      select: { id: true },
    });
    admins.forEach((u) => recipients.add(u.id));
  }

  const storeIds = [...new Set((input.storeIds ?? []).filter(Boolean))];
  if (storeIds.length) {
    const stores = await db.store.findMany({
      where: { id: { in: storeIds } },
      select: { assignedManagerId: true },
    });
    stores.forEach((s) => s.assignedManagerId && recipients.add(s.assignedManagerId));
    if (!input.managersOnly) {
      const users = await db.user.findMany({
        where: { storeId: { in: storeIds }, role: Role.STORE, status: RecordStatus.ACTIVE },
        select: { id: true },
      });
      users.forEach((u) => recipients.add(u.id));
    }
  }

  if (input.excludeUserId) recipients.delete(input.excludeUserId);
  if (!recipients.size) return;

  await db.notification.createMany({
    data: [...recipients].map((userId) => ({
      userId,
      type: input.type,
      title: input.title.slice(0, 150),
      message: input.message.slice(0, 500),
      entityType: input.entityType,
      entityId: input.entityId,
    })),
  });
}

export async function listNotifications(userId: string, q: ListQuery & { unreadOnly?: boolean }) {
  const where = { userId, ...(q.unreadOnly ? { readAt: null } : {}) };
  const [data, total, unread] = await Promise.all([
    prisma.notification.findMany({ where, orderBy: { createdAt: 'desc' }, ...pageArgs(q) }),
    prisma.notification.count({ where }),
    prisma.notification.count({ where: { userId, readAt: null } }),
  ]);
  return { data, total, unread };
}

export const unreadCount = (userId: string) => prisma.notification.count({ where: { userId, readAt: null } });

export async function markRead(userId: string, id: string) {
  const result = await prisma.notification.updateMany({
    where: { id, userId, readAt: null },
    data: { readAt: new Date() },
  });
  if (!result.count) {
    const exists = await prisma.notification.findFirst({ where: { id, userId }, select: { id: true } });
    if (!exists) throw ApiError.notFound('Notification');
  }
}

export async function markAllRead(userId: string) {
  const result = await prisma.notification.updateMany({
    where: { userId, readAt: null },
    data: { readAt: new Date() },
  });
  return result.count;
}
