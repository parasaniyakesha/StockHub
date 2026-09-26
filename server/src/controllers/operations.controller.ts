import { Request, Response } from 'express';
import { ctx } from '../middleware/authorize';
import { created, ok, paginated } from '../utils/response';
import * as stock from '../services/stock.service';
import * as requests from '../services/productRequest.service';
import * as packing from '../services/packingOrder.service';
import * as transfers from '../services/transfer.service';
import * as sales from '../services/sale.service';
import * as returns from '../services/return.service';
import { sendExport } from '../services/export.service';

const v = (req: Request) => req.validated!;
const id = (req: Request) => v(req).params.id as string;

export const stockController = {
  async list(req: Request, res: Response) {
    const q = v(req).query;
    const { rows, total } = await stock.listStock(ctx(req), q);
    paginated(res, rows, { page: q.page, limit: q.limit, total }, 'Stock retrieved successfully');
  },
  async movements(req: Request, res: Response) {
    const q = v(req).query;
    const { rows, total } = await stock.listMovements(ctx(req), q);
    paginated(res, rows, { page: q.page, limit: q.limit, total }, 'Stock movements retrieved successfully');
  },
  async exportMovements(req: Request, res: Response) {
    const { rows } = await stock.listMovements(ctx(req), { ...v(req).query, page: 1 }, 10_000);
    await sendExport(res, (req.query.format as 'csv' | 'xlsx' | 'pdf') ?? 'csv', 'stock-movements', 'Stock Movements', [
      { header: 'Date', value: (r) => r.createdAt, width: 18 },
      { header: 'Location', value: (r) => r.store?.name ?? r.warehouse?.name, width: 18 },
      { header: 'Product', value: (r) => r.product.name, width: 24 },
      { header: 'SKU', value: (r) => r.product.sku, width: 12 },
      { header: 'Type', value: (r) => r.type, width: 12 },
      { header: 'Bucket', value: (r) => r.bucket, width: 10 },
      { header: 'Quantity', value: (r) => r.quantity, numeric: true, width: 10 },
      { header: 'Balance', value: (r) => r.balanceAfter, numeric: true, width: 10 },
      { header: 'Reference', value: (r) => r.referenceType, width: 14 },
      { header: 'Reason', value: (r) => r.reason, width: 24 },
      { header: 'User', value: (r) => r.createdBy.name, width: 16 },
    ], rows);
  },
  async opening(req: Request, res: Response) {
    created(res, await stock.recordOpeningStock(ctx(req), v(req).body), 'Opening stock recorded');
  },
  async purchase(req: Request, res: Response) {
    created(res, await stock.recordPurchase(ctx(req), v(req).body), 'Purchase recorded');
  },
  async adjust(req: Request, res: Response) {
    created(res, await stock.recordAdjustment(ctx(req), v(req).body), 'Stock adjusted');
  },
  async damage(req: Request, res: Response) {
    created(res, await stock.reportDamage(ctx(req), v(req).body), 'Damaged stock reported');
  },
  async writeOff(req: Request, res: Response) {
    created(res, await stock.writeOffDamaged(ctx(req), v(req).body), 'Damaged stock written off');
  },
  async submitAvailability(req: Request, res: Response) {
    created(res, await stock.submitAvailability(ctx(req), v(req).body), 'Availability submitted');
  },
  async availability(req: Request, res: Response) {
    const q = v(req).query;
    const { rows, total } = await stock.listAvailability(ctx(req), q);
    paginated(res, rows, { page: q.page, limit: q.limit, total }, 'Availability retrieved');
  },
  async deleteBalance(req: Request, res: Response) {
    ok(res, await stock.deleteStockBalance(ctx(req), id(req), v(req).query.locationType), 'Stock record removed');
  },
  async availabilityMatrix(req: Request, res: Response) {
    const q = v(req).query;
    const { stores, rows, total } = await stock.availabilityMatrix(ctx(req), q);
    res.json({
      success: true,
      message: 'Availability matrix retrieved',
      data: { stores, rows },
      pagination: { page: q.page, limit: q.limit, total, totalPages: Math.ceil(total / q.limit) },
    });
  },
};

export const requestController = {
  async list(req: Request, res: Response) {
    const q = v(req).query;
    const { rows, total } = await requests.listRequests(ctx(req), q);
    paginated(res, rows, { page: q.page, limit: q.limit, total }, 'Product requests retrieved successfully');
  },
  get: async (req: Request, res: Response) => ok(res, await requests.getRequest(ctx(req), id(req)), 'Product request retrieved'),
  create: async (req: Request, res: Response) => created(res, await requests.createRequest(ctx(req), v(req).body), 'Product request created'),
  update: async (req: Request, res: Response) => ok(res, await requests.updateRequest(ctx(req), id(req), v(req).body), 'Product request updated'),
  submit: async (req: Request, res: Response) => ok(res, await requests.submitRequest(ctx(req), id(req)), 'Product request submitted'),
  review: async (req: Request, res: Response) => ok(res, await requests.startReview(ctx(req), id(req)), 'Review started'),
  approve: async (req: Request, res: Response) => ok(res, await requests.approveRequest(ctx(req), id(req), v(req).body), 'Product request approved'),
  reject: async (req: Request, res: Response) => ok(res, await requests.rejectRequest(ctx(req), id(req), v(req).body.reason), 'Product request rejected'),
  cancel: async (req: Request, res: Response) => ok(res, await requests.cancelRequest(ctx(req), id(req), v(req).body.reason), 'Product request cancelled'),
};

export const packingController = {
  async list(req: Request, res: Response) {
    const q = v(req).query;
    const { rows, total } = await packing.listPackingOrders(ctx(req), q);
    paginated(res, rows, { page: q.page, limit: q.limit, total }, 'Packing orders retrieved successfully');
  },
  get: async (req: Request, res: Response) => ok(res, await packing.getPackingOrder(ctx(req), id(req)), 'Packing order retrieved'),
  create: async (req: Request, res: Response) => created(res, await packing.createPackingOrder(ctx(req), v(req).body), 'Packing order created'),
  fromRequests: async (req: Request, res: Response) => created(res, await packing.createFromRequests(ctx(req), v(req).body), 'Packing order generated'),
  update: async (req: Request, res: Response) => ok(res, await packing.updatePackingOrder(ctx(req), id(req), v(req).body), 'Packing order updated'),
  assign: async (req: Request, res: Response) => ok(res, await packing.assignPackingOrder(ctx(req), id(req)), 'Packing order assigned'),
  startPacking: async (req: Request, res: Response) => ok(res, await packing.startPacking(ctx(req), id(req)), 'Packing started'),
  pack: async (req: Request, res: Response) => ok(res, await packing.markPacked(ctx(req), id(req), v(req).body), 'Packing order packed'),
  dispatch: async (req: Request, res: Response) => ok(res, await packing.dispatchPackingOrder(ctx(req), id(req)), 'Packing order dispatched'),
  receive: async (req: Request, res: Response) => ok(res, await packing.receivePackingOrder(ctx(req), id(req), v(req).body), 'Stock received'),
  complete: async (req: Request, res: Response) => ok(res, await packing.completePackingOrder(ctx(req), id(req)), 'Packing order closed'),
  cancel: async (req: Request, res: Response) => ok(res, await packing.cancelPackingOrder(ctx(req), id(req), v(req).body.reason), 'Packing order cancelled'),
};

export const transferController = {
  async list(req: Request, res: Response) {
    const q = v(req).query;
    const { rows, total } = await transfers.listTransfers(ctx(req), q);
    paginated(res, rows, { page: q.page, limit: q.limit, total }, 'Transfers retrieved successfully');
  },
  get: async (req: Request, res: Response) => ok(res, await transfers.getTransfer(ctx(req), id(req)), 'Transfer retrieved'),
  create: async (req: Request, res: Response) => created(res, await transfers.createTransfer(ctx(req), v(req).body), 'Transfer requested'),
  approve: async (req: Request, res: Response) => ok(res, await transfers.approveTransfer(ctx(req), id(req), v(req).body), 'Transfer approved'),
  reject: async (req: Request, res: Response) => ok(res, await transfers.rejectTransfer(ctx(req), id(req), v(req).body.reason), 'Transfer rejected'),
  dispatch: async (req: Request, res: Response) => ok(res, await transfers.dispatchTransfer(ctx(req), id(req)), 'Transfer dispatched'),
  receive: async (req: Request, res: Response) => ok(res, await transfers.receiveTransfer(ctx(req), id(req), v(req).body), 'Transfer received'),
  complete: async (req: Request, res: Response) => ok(res, await transfers.completeTransfer(ctx(req), id(req)), 'Transfer closed'),
  cancel: async (req: Request, res: Response) => ok(res, await transfers.cancelTransfer(ctx(req), id(req), v(req).body.reason), 'Transfer cancelled'),
};

export const saleController = {
  async list(req: Request, res: Response) {
    const q = v(req).query;
    const { rows, total, summary } = await sales.listSales(ctx(req), q);
    res.json({
      success: true,
      message: 'Sales retrieved successfully',
      data: rows,
      summary,
      pagination: { page: q.page, limit: q.limit, total, totalPages: Math.ceil(total / q.limit) },
    });
  },
  get: async (req: Request, res: Response) => ok(res, await sales.getSale(ctx(req), id(req)), 'Sale retrieved'),
  async create(req: Request, res: Response) {
    const { sale, duplicate } = await sales.createSale(ctx(req), v(req).body);
    // Re-submitting the same clientRequestId returns the original sale (idempotent).
    if (duplicate) return ok(res, sale, 'Sale was already recorded');
    return created(res, sale, 'Sale recorded');
  },
  cancel: async (req: Request, res: Response) => ok(res, await sales.cancelSale(ctx(req), id(req), v(req).body.reason), 'Sale cancelled'),
};

export const returnController = {
  async list(req: Request, res: Response) {
    const q = v(req).query;
    const { rows, total } = await returns.listReturns(ctx(req), q);
    paginated(res, rows, { page: q.page, limit: q.limit, total }, 'Returns retrieved successfully');
  },
  get: async (req: Request, res: Response) => ok(res, await returns.getReturn(ctx(req), id(req)), 'Return retrieved'),
  create: async (req: Request, res: Response) => created(res, await returns.createReturn(ctx(req), v(req).body), 'Return recorded'),
};
