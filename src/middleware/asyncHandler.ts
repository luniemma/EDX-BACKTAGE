import { NextFunction, Request, RequestHandler, Response } from 'express';
import type { ParamsDictionary, Query } from 'express-serve-static-core';

// Generic so typed handlers (e.g. Request<{ id: string }>) stay assignable to
// Express's RequestHandler instead of collapsing to the default ParamsDictionary.
export const asyncHandler =
  <P = ParamsDictionary, ResBody = unknown, ReqBody = unknown, ReqQuery = Query>(
    fn: (
      req: Request<P, ResBody, ReqBody, ReqQuery>,
      res: Response<ResBody>,
      next: NextFunction,
    ) => Promise<unknown>,
  ): RequestHandler<P, ResBody, ReqBody, ReqQuery> =>
  (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
