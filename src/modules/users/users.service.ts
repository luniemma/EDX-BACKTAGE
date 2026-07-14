import { prisma } from '../../db/client';
import { notFound } from '../../utils/httpError';

const publicSelect = {
  id: true,
  email: true,
  name: true,
  role: true,
  createdAt: true,
  updatedAt: true,
} as const;

export function list() {
  return prisma.user.findMany({ select: publicSelect, orderBy: { createdAt: 'desc' } });
}

export async function getById(id: string) {
  const user = await prisma.user.findUnique({ where: { id }, select: publicSelect });
  if (!user) throw notFound('User not found');
  return user;
}
