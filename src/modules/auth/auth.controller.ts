import { Request, Response } from 'express';
import * as authService from './auth.service';
import type { LoginInput, RegisterInput } from './auth.schema';

export async function register(req: Request<unknown, unknown, RegisterInput>, res: Response) {
  const result = await authService.register(req.body);
  res.status(201).json(result);
}

export async function login(req: Request<unknown, unknown, LoginInput>, res: Response) {
  const result = await authService.login(req.body);
  res.json(result);
}

export function me(req: Request, res: Response) {
  res.json({ user: req.user });
}
