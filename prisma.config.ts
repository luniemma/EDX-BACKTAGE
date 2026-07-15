import 'dotenv/config';
import { defineConfig } from 'prisma/config';

// Prisma 7 moved the connection URL out of schema.prisma. The CLI/Migrate reads
// it from here; the runtime client connects via a driver adapter (see src/db/client.ts).
// Plain process.env (not prisma's strict `env()`) so `prisma generate` works even
// when DATABASE_URL is unset — only Migrate/introspection actually need the URL.
export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
    seed: 'tsx prisma/seed.ts',
  },
  datasource: {
    url: process.env.DATABASE_URL,
  },
});
