import { prisma } from '../src/db/client';

beforeEach(async () => {
  // Truncate all data between tests for isolation.
  await prisma.note.deleteMany();
  await prisma.user.deleteMany();
});

afterAll(async () => {
  await prisma.$disconnect();
});
