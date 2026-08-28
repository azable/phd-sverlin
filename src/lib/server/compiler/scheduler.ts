/** Bounded, process-wide admission for memory-heavy compiler children. */

export type CompilePriority = 'foreground' | 'prefetch';

/** Non-sensitive compiler admission state exposed by readiness diagnostics. */
export type CompileSchedulerStatus = {
  accepting: boolean;
  active: CompilePriority | undefined;
  queuedForeground: number;
  queuedPrefetch: number;
};

type QueueEntry<T> = {
  priority: CompilePriority;
  controller: AbortController;
  signal?: AbortSignal;
  run: (signal: AbortSignal) => Promise<T>;
  resolve: (value: T) => void;
  reject: (reason: unknown) => void;
  detachAbort?: () => void;
};

/** Raised before an operation starts when bounded compiler admission is full. */
export class CompileQueueFullError extends Error {
  constructor() {
    super('The compiler queue is full. Try again after an active compilation finishes.');
    this.name = 'CompileQueueFullError';
  }
}

/** Raised when the server is draining and cannot admit more compiler work. */
export class CompilerShuttingDownError extends Error {
  constructor() {
    super('The compiler is shutting down and is not accepting new work.');
    this.name = 'CompilerShuttingDownError';
  }
}

/** One-worker scheduler that gives foreground requests priority over disposable prefetch. */
export class CompileScheduler {
  readonly #maxQueuedForeground: number;
  readonly #queue: QueueEntry<unknown>[] = [];
  #active?: QueueEntry<unknown>;
  #accepting = true;

  constructor(maxQueuedForeground = readMaxQueuedCompiles()) {
    this.#maxQueuedForeground = maxQueuedForeground;
  }

  /** Queue compiler work, cancelling active speculative work for foreground demand. */
  run<T>(
    priority: CompilePriority,
    task: (signal: AbortSignal) => Promise<T>,
    signal?: AbortSignal
  ): Promise<T> {
    if (!this.#accepting) return Promise.reject(new CompilerShuttingDownError());
    if (signal?.aborted) return Promise.reject(abortError());

    if (priority === 'foreground' && this.#active) {
      const queuedForeground = this.#queue.filter(
        (entry) => entry.priority === 'foreground'
      ).length;
      const waitingLimit =
        this.#active.priority === 'prefetch'
          ? Math.max(1, this.#maxQueuedForeground)
          : this.#maxQueuedForeground;
      if (queuedForeground >= waitingLimit) {
        return Promise.reject(new CompileQueueFullError());
      }
    }
    if (
      priority === 'prefetch' &&
      (this.#active?.priority === 'prefetch' ||
        this.#queue.some((entry) => entry.priority === 'prefetch'))
    ) {
      return Promise.reject(new CompileQueueFullError());
    }

    return new Promise<T>((resolve, reject) => {
      const entry: QueueEntry<T> = {
        priority,
        controller: new AbortController(),
        signal,
        run: task,
        resolve,
        reject
      };
      const queuedEntry = entry as unknown as QueueEntry<unknown>;
      if (signal) {
        const abort = () => {
          entry.controller.abort();
          const index = this.#queue.indexOf(queuedEntry);
          if (index >= 0) {
            this.#queue.splice(index, 1);
            entry.detachAbort?.();
            reject(abortError());
          }
        };
        signal.addEventListener('abort', abort, { once: true });
        entry.detachAbort = () => signal.removeEventListener('abort', abort);
      }

      const insertion = this.#queue.findIndex((queued) => queued.priority === 'prefetch');
      if (priority === 'foreground' && insertion >= 0) {
        this.#queue.splice(insertion, 0, queuedEntry);
      } else {
        this.#queue.push(queuedEntry);
      }

      if (priority === 'foreground' && this.#active?.priority === 'prefetch') {
        this.#active.controller.abort();
      }
      this.#pump();
    });
  }

  /** Stop admission and cancel queued/speculative work for graceful shutdown. */
  shutdown(): void {
    this.#accepting = false;
    for (const entry of this.#queue.splice(0)) {
      entry.detachAbort?.();
      entry.reject(new CompilerShuttingDownError());
    }
    if (this.#active?.priority === 'prefetch') this.#active.controller.abort();
  }

  /** Current non-sensitive scheduler state for readiness and diagnostics. */
  status(): CompileSchedulerStatus {
    return {
      accepting: this.#accepting,
      active: this.#active?.priority,
      queuedForeground: this.#queue.filter(({ priority }) => priority === 'foreground').length,
      queuedPrefetch: this.#queue.filter(({ priority }) => priority === 'prefetch').length
    };
  }

  #pump() {
    if (this.#active || !this.#accepting) return;
    const next = this.#queue.shift();
    if (!next) return;
    this.#active = next;
    const combined = next.signal
      ? AbortSignal.any([next.signal, next.controller.signal])
      : next.controller.signal;
    void (async () => {
      try {
        const value = await next.run(combined);
        next.detachAbort?.();
        if (this.#active === next) this.#active = undefined;
        this.#pump();
        next.resolve(value);
      } catch (error) {
        next.detachAbort?.();
        if (this.#active === next) this.#active = undefined;
        this.#pump();
        next.reject(error);
      }
    })();
  }
}

/** Shared scheduler used by all requests, including across Vite server-module reloads. */
const schedulerKey = Symbol.for('sverlin.compiler-scheduler');
const sharedScheduler = globalThis as typeof globalThis & {
  [schedulerKey]?: CompileScheduler;
};
export const compilerScheduler = (sharedScheduler[schedulerKey] ??= new CompileScheduler());

function readMaxQueuedCompiles() {
  const value = Number(process.env.SVERLIN_MAX_QUEUED_COMPILES ?? '3');
  return Number.isSafeInteger(value) && value >= 0 ? value : 3;
}

function abortError() {
  return new DOMException('The compiler request was cancelled.', 'AbortError');
}
