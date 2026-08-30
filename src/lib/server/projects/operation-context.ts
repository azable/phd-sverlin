/** Async context used to propagate operation cancellation through service boundaries. */

import { AsyncLocalStorage } from 'node:async_hooks';

const operationSignals = new AsyncLocalStorage<AbortSignal>();

export function runWithProjectOperationSignal<T>(
  signal: AbortSignal,
  callback: () => Promise<T>
): Promise<T> {
  return operationSignals.run(signal, callback);
}

export function currentProjectOperationSignal(): AbortSignal | undefined {
  return operationSignals.getStore();
}
