import { Response } from 'express';

export interface PaginationMeta {
  page: number;
  limit: number;
  total: number;
  totalPages: number;
}

export function ok<T>(res: Response, data: T, message = 'Success', status = 200) {
  return res.status(status).json({ success: true, message, data });
}

export function created<T>(res: Response, data: T, message = 'Created successfully') {
  return ok(res, data, message, 201);
}

export function paginated<T>(
  res: Response,
  data: T[],
  meta: { page: number; limit: number; total: number },
  message = 'Records retrieved successfully',
) {
  const pagination: PaginationMeta = {
    ...meta,
    totalPages: meta.limit > 0 ? Math.ceil(meta.total / meta.limit) : 0,
  };
  return res.status(200).json({ success: true, message, data, pagination });
}
