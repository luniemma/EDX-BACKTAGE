import { NextFunction, Request, Response } from 'express';
import { verifyToken, JwtPayload } from '../utils/jwt';
import { forbidden, unauthorized } from '../utils/httpError';

declare module 'express-serve-static-core' {
  interface Request {
    user?: JwtPayload;
  }
}

export const requireAuth = (req: Request, _res: Response, next: NextFunction) => {
  const header = req.header('authorization') ?? req.header('Authorization');
  if (!header?.startsWith('Bearer ')) {
    next(unauthorized('Missing or malformed Authorization header'));
    return;
  }
  const token = header.slice('Bearer '.length).trim();
  try {
    req.user = verifyToken(token);
    next();
  } catch {
    next(unauthorized('Invalid or expired token'));
  }
};

export const requireRole =
  (...roles: Array<'USER' | 'ADMIN'>) =>
  (req: Request, _res: Response, next: NextFunction) => {
    if (!req.user) {
      next(unauthorized());
      return;
    }
    if (!roles.includes(req.user.role)) {
      next(forbidden('Insufficient role'));
      return;
    }
    next();
  };
