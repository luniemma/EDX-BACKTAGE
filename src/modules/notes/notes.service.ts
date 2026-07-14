import { prisma } from '../../db/client';
import { forbidden, notFound } from '../../utils/httpError';
import type { CreateNoteInput, UpdateNoteInput } from './notes.schema';

export function listForUser(userId: string) {
  return prisma.note.findMany({
    where: { authorId: userId },
    orderBy: { createdAt: 'desc' },
  });
}

export async function getForUser(id: string, userId: string, isAdmin: boolean) {
  const note = await prisma.note.findUnique({ where: { id } });
  if (!note) throw notFound('Note not found');
  if (note.authorId !== userId && !isAdmin) throw forbidden();
  return note;
}

export function create(userId: string, input: CreateNoteInput) {
  return prisma.note.create({
    data: { ...input, authorId: userId },
  });
}

export async function update(id: string, userId: string, isAdmin: boolean, input: UpdateNoteInput) {
  await getForUser(id, userId, isAdmin);
  return prisma.note.update({ where: { id }, data: input });
}

export async function remove(id: string, userId: string, isAdmin: boolean) {
  await getForUser(id, userId, isAdmin);
  await prisma.note.delete({ where: { id } });
}
