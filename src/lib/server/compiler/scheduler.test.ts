import { describe, expect, it } from 'vitest';

import { CompileQueueFullError, CompileScheduler } from './scheduler';

describe('CompileScheduler', () => {
  it('serializes compiler work in submission order', async () => {
    const scheduler = new CompileScheduler(3);
    const first = deferred<void>();
    const order: string[] = [];
    const active = scheduler.run(async () => {
      order.push('first-start');
      await first.promise;
      order.push('first-end');
    });
    const queued = scheduler.run(async () => {
      order.push('second');
    });

    await Promise.resolve();
    expect(order).toEqual(['first-start']);
    first.resolve();
    await Promise.all([active, queued]);
    expect(order).toEqual(['first-start', 'first-end', 'second']);
  });

  it('rejects excess work before it starts', async () => {
    const scheduler = new CompileScheduler(1);
    const activeGate = deferred<void>();
    const active = scheduler.run(() => activeGate.promise);
    const queued = scheduler.run(async () => undefined);

    await expect(scheduler.run(async () => undefined)).rejects.toBeInstanceOf(
      CompileQueueFullError
    );
    activeGate.resolve();
    await Promise.all([active, queued]);
  });

  it('allows immediate work but no waiting work when the queue limit is zero', async () => {
    const scheduler = new CompileScheduler(0);
    const activeGate = deferred<void>();
    const active = scheduler.run(() => activeGate.promise);

    await expect(scheduler.run(async () => undefined)).rejects.toBeInstanceOf(
      CompileQueueFullError
    );
    activeGate.resolve();
    await active;
    await expect(scheduler.run(async () => 'done')).resolves.toBe('done');
  });

  it('cancels active work during shutdown', async () => {
    const scheduler = new CompileScheduler(1);
    const events: string[] = [];
    const active = scheduler.run(async (signal) => {
      events.push('active-start');
      await aborted(signal);
      events.push('active-aborted');
    });
    await Promise.resolve();
    scheduler.shutdown();
    await active;
    expect(events).toEqual(['active-start', 'active-aborted']);
  });
});

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  const promise = new Promise<T>((complete) => {
    resolve = complete;
  });
  return { promise, resolve };
}

function aborted(signal: AbortSignal) {
  if (signal.aborted) return Promise.resolve();
  return new Promise<void>((resolve) =>
    signal.addEventListener('abort', () => resolve(), { once: true })
  );
}
