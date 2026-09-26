import { RequestContext } from './auth';

declare global {
  namespace Express {
    interface Request {
      ctx?: RequestContext;
      /** Validated & coerced input set by the validate() middleware. */
      validated?: { body?: any; query?: any; params?: any };
    }
  }
}

export {};
