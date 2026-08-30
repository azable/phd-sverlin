import { describe, expect, it } from 'vitest';

import type { ProjectDocument } from '$lib/shared/projects/model';

import { projectWorkspace } from './workspace-view';

const operationId = '12345678-1234-4123-8123-123456789abc';

describe('workspace projection', () => {
  it('returns the complete authorized Timeline for client-side participant projection', () => {
    const document: ProjectDocument = {
      schemaVersion: 1,
      projectId: 'workspace-test',
      events: [
        {
          id: 1,
          type: 'project.created',
          actor: { kind: 'user' },
          operationId,
          createdAt: '2026-01-01T00:00:00.000Z',
          payload: { title: 'Test', entryArtifactId: 'dsl-main' }
        },
        {
          id: 2,
          type: 'feedback.submitted',
          actor: { kind: 'user' },
          operationId,
          createdAt: '2026-01-01T00:00:01.000Z',
          payload: { text: 'Make it clearer', focus: [] }
        },
        {
          id: 3,
          type: 'assistant.responded',
          actor: { kind: 'assistant', botId: 'sverlin-assistant' },
          operationId,
          createdAt: '2026-01-01T00:00:02.000Z',
          payload: { text: 'I simplified the labels.' }
        }
      ]
    };
    const workspace = projectWorkspace({
      document,
      projects: [],
      view: 'participant',
      layout: 'single'
    });
    expect(workspace.document).toEqual(document);
    expect(workspace.document.events.map(({ type }) => type)).toEqual([
      'project.created',
      'feedback.submitted',
      'assistant.responded'
    ]);
    expect(workspace.readOnly).toBe(false);
    expect(workspace.userAuthorLabel).toBe('You');
    expect(
      projectWorkspace({
        document,
        projects: [],
        view: 'participant',
        layout: 'single',
        readOnly: true,
        userAuthorLabel: 'P-104'
      })
    ).toMatchObject({ readOnly: true, userAuthorLabel: 'P-104' });
  });
});
