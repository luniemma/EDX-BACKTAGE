import { Request, Response } from 'express';
import { unauthorized } from '../../utils/httpError';
import * as notesService from './notes.service';
import type { CreateNoteInput, UpdateNoteInput } from './notes.schema';

function requireUser(req: Request) {
  if (!req.user) throw unauthorized();
  return { id: req.user.sub, isAdmin: req.user.role === 'ADMIN' };
}

export async function list(req: Request, res: Response) {
  const { id } = requireUser(req);
  res.json(await notesService.listForUser(id));
}

export async function getOne(req: Request<{ id: string }>, res: Response) {
  const { id: userId, isAdmin } = requireUser(req);
  res.json(await notesService.getForUser(req.params.id, userId, isAdmin));
}

export async function create(req: Request<unknown, unknown, CreateNoteInput>, res: Response) {
  const { id } = requireUser(req);
  const note = await notesService.create(id, req.body);
  res.status(201).json(note);
}

export async function update(req: Request<{ id: string }, unknown, UpdateNoteInput>, res: Response) {
  const { id: userId, isAdmin } = requireUser(req);
  res.json(await notesService.update(req.params.id, userId, isAdmin, req.body));
}

export async function remove(req: Request<{ id: string }>, res: Response) {
  const { id: userId, isAdmin } = requireUser(req);
  await notesService.remove(req.params.id, userId, isAdmin);
  res.status(204).send();
}
