/** Apply checked-in Drizzle migrations from the production image. */

import path from 'node:path';

import { migrate } from 'drizzle-orm/postgres-js/migrator';

import { closeDatabase, database } from '$lib/server/db';

if (!process.env.DATABASE_URL?.trim()) throw new Error('DATABASE_URL is required.');

try {
  await migrate(database(), { migrationsFolder: path.resolve('drizzle') });
  console.info('Sverlin PostgreSQL migrations are current.');
} finally {
  await closeDatabase();
}
