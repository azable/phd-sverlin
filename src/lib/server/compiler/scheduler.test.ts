import { describe, expect, it } from 'vitest';

import { CompileQueueFullError, CompileScheduler } from './scheduler';

describe('CompileScheduler', () => {
  it('serializes compiler work and preserves foreground order', async () => {
    const scheduler = new CompileScheduler(3);
    const first = deferred<void>();
    const order: string[] = [];
    const active = scheduler.run('foreground', async () => {
      order.push('first-start');
      await first.promise;
      order.push('first-end');
    });
    const queued = scheduler.run('foreground', async () => {
      order.push('second');
    });

    await Promise.resolve();
    expect(order).toEqual(['first-start']);
    first.resolve();
    await Promise.all([active, queued]);
    expect(order).toEqual(['first-start', 'first-end', 'second']);
  });

  it('rejects excess foreground work before it starts', async () => {
    const scheduler = new CompileScheduler(1);
    const activeGate = deferred<void>();
    const active = scheduler.run('foreground', () => activeGate.promise);
    const queued = scheduler.run('foreground', async () => undefined);

    await expect(scheduler.run('foreground', async () => undefined)).rejects.toBeInstanceOf(
      CompileQueueFullError
    );
    activeGate.resolve();
    await Promise.all([active, queued]);
  });

  it('allows immediate work but no waiting work when the queue limit is zero', async () => {
    const scheduler = new CompileScheduler(0);
    const activeGate = deferred<void>();
    const active = scheduler.run('foreground', () => activeGate.promise);

    await expect(scheduler.run('foreground', async () => undefined)).rejects.toBeInstanceOf(
      CompileQueueFullError
    );
    activeGate.resolve();
    await active;
    await expect(scheduler.run('foreground', async () => 'done')).resolves.toBe('done');
  });

  it('cancels disposable prefetch when foreground work arrives', async () => {
    const scheduler = new CompileScheduler(1);
    const events: string[] = [];
    const prefetch = scheduler.run('prefetch', async (signal) => {
      events.push('prefetch-start');
      await aborted(signal);
      events.push('prefetch-aborted');
    });
    await Promise.resolve();
    const foreground = scheduler.run('foreground', async () => {
      events.push('foreground');
    });

    await Promise.all([prefetch, foreground]);
    expect(events).toEqual(['prefetch-start', 'prefetch-aborted', 'foreground']);
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
