import { Request, Response } from 'express';
import * as usersService from './users.service';

export async function list(_req: Request, res: Response) {
  res.json(await usersService.list());
}

export async function getOne(req: Request<{ id: string }>, res: Response) {
  res.json(await usersService.getById(req.params.id));
}
