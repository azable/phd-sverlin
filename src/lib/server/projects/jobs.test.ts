import { describe, expect, it } from 'vitest';

import type { ProjectEvent } from '$lib/shared/projects/events';

import {
  projectOperationHasCompleted,
  projectOperationWasInterrupted,
  type QueuedProjectCommand
} from './jobs';

describe('durable project job completion', () => {
  it('does not mistake a partial render append for a completed command', () => {
    const command = { type: 'render' } as QueuedProjectCommand;

    expect(projectOperationHasCompleted(command, events('compilation.requested'))).toBe(false);
    expect(projectOperationHasCompleted(command, events('compilation.succeeded'))).toBe(false);
    expect(projectOperationHasCompleted(command, events('compilation.failed'))).toBe(true);
    expect(projectOperationHasCompleted(command, events('visualization.rendered'))).toBe(true);
  });

  it('uses the command-specific final response for feedback and rename jobs', () => {
    const feedback = { type: 'feedback' } as QueuedProjectCommand;
    const rename = { type: 'rename' } as QueuedProjectCommand;

    expect(projectOperationHasCompleted(feedback, events('ai.generation-succeeded'))).toBe(false);
    expect(projectOperationHasCompleted(feedback, events('assistant.responded'))).toBe(true);
    expect(projectOperationHasCompleted(feedback, events('system.notified'))).toBe(true);
    expect(projectOperationHasCompleted(rename, events('project.renamed'))).toBe(true);
  });

  it('preserves a failed outcome when a retry observes recovery terminal events', () => {
    const recovered = [
      {
        type: 'compilation.failed',
        payload: { failureKind: 'cancelled' }
      } as ProjectEvent
    ];

    expect(
      projectOperationHasCompleted({ type: 'render' } as QueuedProjectCommand, recovered)
    ).toBe(true);
    expect(projectOperationWasInterrupted(recovered)).toBe(true);
  });
});

function events(...types: ProjectEvent['type'][]): ProjectEvent[] {
  return types.map((type) => ({ type }) as ProjectEvent);
}
