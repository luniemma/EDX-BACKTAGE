import { Router } from 'express';
import { asyncHandler } from '../../middleware/asyncHandler';
import { requireAuth, requireRole } from '../../middleware/auth';
import * as controller from './users.controller';

export const usersRouter = Router();

usersRouter.use(requireAuth);
usersRouter.get('/', requireRole('ADMIN'), asyncHandler(controller.list));
usersRouter.get('/:id', asyncHandler(controller.getOne));
