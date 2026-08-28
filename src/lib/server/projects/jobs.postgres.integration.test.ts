import { randomUUID } from 'node:crypto';

import { PgBoss } from 'pg-boss';
import { expect, it } from 'vitest';

const connectionString = process.env.DATABASE_URL;
const postgresTestsEnabled = process.env.SVERLIN_RUN_POSTGRES_TESTS === '1';

it.skipIf(!connectionString || !postgresTestsEnabled)(
  'persists, resumes, completes, cancels, and deletes jobs through PostgreSQL',
  async () => {
    const queue = `sverlin-test-${randomUUID()}`;
    const producer = createBoss(connectionString!);
    await producer.start();
    await producer.createQueue(queue);
    const durableJobId = await producer.send(queue, { sequence: 1 });
    expect(durableJobId).toBeTruthy();
    await producer.stop({ graceful: true });

    const worker = createBoss(connectionString!);
    try {
      await worker.start();
      const completed = new Promise<void>((resolve) => {
        void worker.work<{ sequence: number }>(
          queue,
          { pollingIntervalSeconds: 1 },
          async ([job]) => {
            expect(job.id).toBe(durableJobId);
            expect(job.data).toEqual({ sequence: 1 });
            resolve();
            return { accepted: true };
          }
        );
      });
      await completed;
      await expectState(worker, queue, durableJobId!, 'completed');

      const cancelledJobId = await worker.send(queue, { sequence: 2 });
      expect(cancelledJobId).toBeTruthy();
      await worker.cancel(queue, cancelledJobId!);
      await expectState(worker, queue, cancelledJobId!, 'cancelled');
      await worker.deleteJob(queue, cancelledJobId!);
      expect(await worker.findJobs(queue, { id: cancelledJobId! })).toEqual([]);
    } finally {
      await worker.offWork(queue).catch(() => undefined);
      await worker.deleteQueue(queue).catch(() => undefined);
      await worker.stop({ graceful: true });
    }
  },
  30_000
);

function createBoss(databaseUrl: string): PgBoss {
  const boss = new PgBoss({ connectionString: databaseUrl, application_name: 'sverlin-tests' });
  boss.on('error', () => undefined);
  return boss;
}

async function expectState(
  boss: PgBoss,
  queue: string,
  id: string,
  state: 'completed' | 'cancelled'
): Promise<void> {
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    const [job] = await boss.findJobs(queue, { id });
    if (job?.state === state) return;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  expect((await boss.findJobs(queue, { id }))[0]?.state).toBe(state);
}
