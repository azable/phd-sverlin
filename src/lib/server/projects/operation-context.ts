/** Async context used to propagate operation cancellation through service boundaries. */

import { AsyncLocalStorage } from 'node:async_hooks';

type ProjectOperationContext = {
  signal: AbortSignal;
  deadlineAt?: number;
};

const operationContexts = new AsyncLocalStorage<ProjectOperationContext>();

export function runWithProjectOperationSignal<T>(
  signal: AbortSignal,
  callback: () => Promise<T>,
  deadlineAt?: number
): Promise<T> {
  return operationContexts.run(
    { signal, ...(deadlineAt === undefined ? {} : { deadlineAt }) },
    callback
  );
}

export function currentProjectOperationSignal(): AbortSignal | undefined {
  return operationContexts.getStore()?.signal;
}

/** Absolute study-phase deadline for the current operation, when one applies. */
export function currentProjectOperationDeadline(): number | undefined {
  return operationContexts.getStore()?.deadlineAt;
}

/** Fail immediately before publishing a result if cancellation or a phase deadline won the race. */
export function assertCurrentProjectOperationActive(): void {
  const context = operationContexts.getStore();
  if (context?.signal.aborted) throw context.signal.reason ?? abortError();
  if (context?.deadlineAt !== undefined && Date.now() >= context.deadlineAt) {
    throw projectOperationDeadlineError();
  }
}

/** Shared cancellation reason for work that reaches its server-authoritative study deadline. */
export function projectOperationDeadlineError(): Error {
  const error = new Error(
    'The study phase ended before this project operation could finish. The last working visualization was kept.'
  );
  error.name = 'StudyPhaseDeadlineError';
  return error;
}

function abortError(): Error {
  const error = new Error('The project operation was cancelled.');
  error.name = 'AbortError';
  return error;
}
