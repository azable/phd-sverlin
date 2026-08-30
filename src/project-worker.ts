/** pg-boss project command worker for the production worker service. */

import { compilerScheduler } from '$lib/server/compiler/scheduler';
import { closeDatabase } from '$lib/server/db';
import { projectJobExpirationSeconds, startProjectJobWorker } from '$lib/server/projects/jobs';

if (!process.env.DATABASE_URL?.trim()) throw new Error('DATABASE_URL is required.');

const boss = await startProjectJobWorker();
console.info('Sverlin project worker started.');

await new Promise<void>((resolve) => {
  process.once('SIGINT', resolve);
  process.once('SIGTERM', resolve);
});

console.info('Sverlin project worker is draining before shutdown.');
await boss.stop({
  graceful: true,
  timeout: workerShutdownSeconds() * 1_000
});
await compilerScheduler.shutdown();
await closeDatabase();
console.info('Sverlin project worker stopped.');

function workerShutdownSeconds(): number {
  const fallback = projectJobExpirationSeconds() + 60;
  const configured = Number(process.env.SVERLIN_WORKER_SHUTDOWN_SECONDS ?? fallback);
  return Number.isSafeInteger(configured) && configured > 0 ? configured : fallback;
}
