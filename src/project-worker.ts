/** pg-boss project command worker for the Railway worker service. */

import { compilerScheduler } from '$lib/server/compiler/scheduler';
import { closeDatabase } from '$lib/server/db';
import { projectJobExpirationSeconds, startProjectJobWorker } from '$lib/server/projects/jobs';
import { validateProjectResourceStorageConfiguration } from '$lib/server/projects/resource-store';

if (!process.env.DATABASE_URL?.trim()) throw new Error('DATABASE_URL is required.');
validateProjectResourceStorageConfiguration();

const boss = await startProjectJobWorker();
console.info('Sverlin project worker started.');

await new Promise<void>((resolve) => {
  process.once('SIGINT', resolve);
  process.once('SIGTERM', resolve);
});

console.info('Sverlin project worker is draining before shutdown.');
await boss.stop({
  graceful: true,
  timeout: (projectJobExpirationSeconds() + 60) * 1_000
});
await compilerScheduler.shutdown();
await closeDatabase();
console.info('Sverlin project worker stopped.');
