export type ErrorCode =
  | 'BAD_REQUEST'
  | 'VALIDATION_ERROR'
  | 'UNAUTHORIZED'
  | 'TOKEN_EXPIRED'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'INSUFFICIENT_STOCK'
  | 'INVALID_STATE'
  | 'RATE_LIMITED'
  | 'INTERNAL_ERROR';

export interface FieldError {
  field: string;
  message: string;
}

/** Operational error that is safe to show to the client. */
export class ApiError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: ErrorCode,
    message: string,
    public readonly errors?: FieldError[],
  ) {
    super(message);
    this.name = 'ApiError';
  }

  static badRequest(message: string, errors?: FieldError[]) {
    return new ApiError(400, 'BAD_REQUEST', message, errors);
  }
  static validation(errors: FieldError[]) {
    return new ApiError(422, 'VALIDATION_ERROR', 'Please correct the highlighted fields', errors);
  }
  static unauthorized(message = 'Authentication required') {
    return new ApiError(401, 'UNAUTHORIZED', message);
  }
  static forbidden(message = 'Unauthorized access') {
    return new ApiError(403, 'FORBIDDEN', message);
  }
  static notFound(entity = 'Record') {
    return new ApiError(404, 'NOT_FOUND', `${entity} not found`);
  }
  static conflict(message: string) {
    return new ApiError(409, 'CONFLICT', message);
  }
  static insufficientStock(message: string) {
    return new ApiError(409, 'INSUFFICIENT_STOCK', message);
  }
  static invalidState(message: string) {
    return new ApiError(409, 'INVALID_STATE', message);
  }
}
