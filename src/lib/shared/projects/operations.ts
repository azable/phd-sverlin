/** Pure projections for asynchronous operation state recorded in a project Timeline. */

import type { EventId, ProjectEvent, ProjectOperationKind } from './events';
import type { ProjectDocument } from './model';

/** Current state of one accepted project operation. */
export type ProjectOperation = {
  operationId: string;
  kind: ProjectOperationKind;
  acceptedEventId: EventId;
  status: 'accepted' | 'running' | 'completed' | 'failed';
  terminalEvent?: Extract<ProjectEvent, { type: 'operation.completed' | 'operation.failed' }>;
};

/** Reconstruct every explicitly accepted operation in Timeline order. */
export function projectOperations(
  value: ProjectDocument | readonly ProjectEvent[]
): ProjectOperation[] {
  const events = 'events' in value ? value.events : value;
  const operations = new Map<string, ProjectOperation>();

  for (const event of events) {
    if (event.type === 'operation.accepted') {
      operations.set(event.operationId, {
        operationId: event.operationId,
        kind: event.payload.kind,
        acceptedEventId: event.id,
        status: 'accepted'
      });
      continue;
    }
    const operation = operations.get(event.operationId);
    if (!operation || operation.terminalEvent) continue;
    if (event.type === 'operation.completed' || event.type === 'operation.failed') {
      operation.status = event.type === 'operation.completed' ? 'completed' : 'failed';
      operation.terminalEvent = event;
    } else {
      operation.status = 'running';
    }
  }
  return [...operations.values()];
}

/** Find an explicitly accepted operation by its opaque correlation identifier. */
export function projectOperation(
  value: ProjectDocument | readonly ProjectEvent[],
  operationId: string
): ProjectOperation | undefined {
  return projectOperations(value).find((operation) => operation.operationId === operationId);
}

/** Return the sole unfinished operation, if the project is currently busy. */
export function activeProjectOperation(
  value: ProjectDocument | readonly ProjectEvent[]
): ProjectOperation | undefined {
  return projectOperations(value).find(
    ({ status }) => status === 'accepted' || status === 'running'
  );
}
