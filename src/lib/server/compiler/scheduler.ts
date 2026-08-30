/** Bounded, process-wide admission for memory-heavy compiler children. */

/** Non-sensitive compiler admission state exposed by readiness diagnostics. */
export type CompileSchedulerStatus = {
  accepting: boolean;
  active: boolean;
  queued: number;
};

type QueueEntry<T> = {
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

/** One-process scheduler that serializes memory-heavy visualization generation. */
export class CompileScheduler {
  readonly #maxQueuedForeground: number;
  readonly #queue: QueueEntry<unknown>[] = [];
  #active?: QueueEntry<unknown>;
  #accepting = true;

  constructor(maxQueuedForeground = readMaxQueuedCompiles()) {
    this.#maxQueuedForeground = maxQueuedForeground;
  }

  /** Queue compiler work within a small, explicit admission bound. */
  run<T>(task: (signal: AbortSignal) => Promise<T>, signal?: AbortSignal): Promise<T> {
    if (!this.#accepting) return Promise.reject(new CompilerShuttingDownError());
    if (signal?.aborted) return Promise.reject(abortError());

    if (this.#active && this.#queue.length >= this.#maxQueuedForeground) {
      return Promise.reject(new CompileQueueFullError());
    }

    return new Promise<T>((resolve, reject) => {
      const entry: QueueEntry<T> = {
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

      this.#queue.push(queuedEntry);
      this.#pump();
    });
  }

  /** Stop admission and cancel queued or active work for graceful shutdown. */
  shutdown(): void {
    this.#accepting = false;
    for (const entry of this.#queue.splice(0)) {
      entry.detachAbort?.();
      entry.reject(new CompilerShuttingDownError());
    }
    this.#active?.controller.abort();
  }

  /** Current non-sensitive scheduler state for readiness and diagnostics. */
  status(): CompileSchedulerStatus {
    return {
      accepting: this.#accepting,
      active: Boolean(this.#active),
      queued: this.#queue.length
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
