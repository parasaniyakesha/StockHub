import { Request, Response } from 'express';
import { ctx } from '../middleware/authorize';
import { ok, paginated } from '../utils/response';
import * as notifications from '../services/notification.service';
import * as settings from '../services/settings.service';
import * as auditLogs from '../services/auditLog.service';
import * as reports from '../services/report.service';
import { getDashboard } from '../services/dashboard.service';
import { sendExport } from '../services/export.service';
import { MANAGER_ASSIGNABLE_PERMISSIONS } from '../config/permissions';

const v = (req: Request) => req.validated!;

export const dashboardController = {
  get: async (req: Request, res: Response) => ok(res, await getDashboard(ctx(req), v(req).query), 'Dashboard retrieved'),
};

export const notificationController = {
  async list(req: Request, res: Response) {
    const q = v(req).query;
    const { data, total, unread } = await notifications.listNotifications(ctx(req).user.id, q);
    res.json({
      success: true,
      message: 'Notifications retrieved',
      data,
      unread,
      pagination: { page: q.page, limit: q.limit, total, totalPages: Math.ceil(total / q.limit) },
    });
  },
  unreadCount: async (req: Request, res: Response) => ok(res, { unread: await notifications.unreadCount(ctx(req).user.id) }, 'Unread count'),
  async markRead(req: Request, res: Response) {
    await notifications.markRead(ctx(req).user.id, v(req).params.id);
    ok(res, null, 'Notification marked as read');
  },
  markAllRead: async (req: Request, res: Response) => ok(res, { updated: await notifications.markAllRead(ctx(req).user.id) }, 'All notifications marked as read'),
};

export const settingsController = {
  get: async (_req: Request, res: Response) => ok(res, await settings.getSettings(), 'Settings retrieved'),
  update: async (req: Request, res: Response) => ok(res, await settings.updateSettings(ctx(req), v(req).body), 'Settings updated'),
  permissions: async (_req: Request, res: Response) => ok(res, { managerAssignable: MANAGER_ASSIGNABLE_PERMISSIONS }, 'Permissions retrieved'),
};

export const auditController = {
  async list(req: Request, res: Response) {
    const q = v(req).query;
    const { rows, total } = await auditLogs.listAuditLogs(q);
    paginated(res, rows, { page: q.page, limit: q.limit, total }, 'Audit logs retrieved');
  },
  facets: async (_req: Request, res: Response) => ok(res, await auditLogs.auditFacets(), 'Audit facets'),
  async export(req: Request, res: Response) {
    const { rows } = await auditLogs.listAuditLogs({ ...v(req).query, page: 1 }, 10_000);
    await sendExport(res, (req.query.format as 'csv' | 'xlsx' | 'pdf') ?? 'csv', 'audit-log', 'Audit Log', [
      { header: 'Time', value: (r) => r.createdAt, width: 18 },
      { header: 'User', value: (r) => r.user?.name ?? 'System', width: 16 },
      { header: 'Module', value: (r) => r.module, width: 14 },
      { header: 'Action', value: (r) => r.action, width: 14 },
      { header: 'Summary', value: (r) => r.summary, width: 40 },
      { header: 'Record', value: (r) => r.recordId, width: 20 },
      { header: 'IP', value: (r) => r.ipAddress, width: 14 },
    ], rows);
  },
};

type ReportFn = (context: ReturnType<typeof ctx>, q: reports.ReportQuery) => Promise<reports.Report>;

/** Every report supports JSON (paged) or CSV/XLSX/PDF export via ?format=. */
const runReport = (fn: ReportFn, file: string) => async (req: Request, res: Response) => {
  const q = v(req).query as reports.ReportQuery;
  const report = await fn(ctx(req), q);
  if (q.format !== 'json') {
    return sendExport(res, q.format, `${file}-${(q.type ?? q.groupBy ?? 'report').toLowerCase()}`, report.title, reports.exportColumns(report), report.rows);
  }
  const start = (q.page - 1) * q.limit;
  res.json({
    success: true,
    message: `${report.title} report generated`,
    data: { title: report.title, columns: report.columns, rows: report.rows.slice(start, start + q.limit), summary: report.summary ?? null },
    pagination: { page: q.page, limit: q.limit, total: report.rows.length, totalPages: Math.ceil(report.rows.length / q.limit) },
  });
};

export const reportController = {
  stock: runReport(reports.stockReport, 'stock'),
  sales: runReport(reports.salesReport, 'sales'),
  operations: runReport(reports.operationsReport, 'operations'),
  stores: runReport(reports.storesReport, 'stores'),
};
