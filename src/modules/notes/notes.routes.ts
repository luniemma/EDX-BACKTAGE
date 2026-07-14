import { Router } from 'express';
import { asyncHandler } from '../../middleware/asyncHandler';
import { requireAuth } from '../../middleware/auth';
import { validate } from '../../middleware/validate';
import * as controller from './notes.controller';
import { createNoteSchema, updateNoteSchema } from './notes.schema';

export const notesRouter = Router();

notesRouter.use(requireAuth);
notesRouter.get('/', asyncHandler(controller.list));
notesRouter.get('/:id', asyncHandler(controller.getOne));
notesRouter.post('/', validate(createNoteSchema), asyncHandler(controller.create));
notesRouter.patch('/:id', validate(updateNoteSchema), asyncHandler(controller.update));
notesRouter.delete('/:id', asyncHandler(controller.remove));
