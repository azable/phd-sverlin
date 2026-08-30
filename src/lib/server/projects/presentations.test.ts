import { randomUUID } from 'node:crypto';

import { describe, expect, it, vi } from 'vitest';

import type { ProjectDocument } from '$lib/shared/projects/model';
import { recordText } from './fingerprints';
import { MemoryProjectRepository } from './memory-repository.test-support';
import { recordProjectPreference } from './presentations';
import type { ProjectServiceDependencies } from './service';

describe('presentation commands', () => {
  it('records preferences against stable presentation UUIDs rather than event positions', async () => {
    const repository = new MemoryProjectRepository();
    const displaySetId = randomUUID();
    const presentations = [randomUUID(), randomUUID()] as [string, string];
    const document = comparisonDocument(randomUUID(), displaySetId, presentations);
    await repository.create(document, 'owner');
    const projectService = {
      repository,
      compiler: {} as ProjectServiceDependencies['compiler'],
      readDslRevision: vi.fn()
    };

    const result = await recordProjectPreference(
      {
        projectId: document.projectId,
        expectedHead: document.events.length,
        presentations,
        preferred: presentations[1],
        step: 0,
        visualSelections: [],
        operationId: randomUUID()
      },
      { repository, projectService }
    );

    expect(result.appendedEvents).toEqual([
      expect.objectContaining({
        type: 'visualization.preference-recorded',
        payload: {
          displaySetId,
          presentations,
          preferred: presentations[1],
          step: 0,
          visualSelections: []
        }
      })
    ]);
  });

  it('records compatible historical comparisons without inventing a shared display set', async () => {
    const repository = new MemoryProjectRepository();
    const presentations = [randomUUID(), randomUUID()] as [string, string];
    const document = comparisonDocument(randomUUID(), [randomUUID(), randomUUID()], presentations);
    await repository.create(document, 'owner');
    const projectService = {
      repository,
      compiler: {} as ProjectServiceDependencies['compiler'],
      readDslRevision: vi.fn()
    };

    const result = await recordProjectPreference(
      {
        projectId: document.projectId,
        expectedHead: document.events.length,
        presentations,
        preferred: presentations[0],
        step: 0,
        visualSelections: [],
        operationId: randomUUID()
      },
      { repository, projectService }
    );

    expect(result.appendedEvents[0]).toMatchObject({
      type: 'visualization.preference-recorded',
      payload: { presentations, preferred: presentations[0], step: 0, visualSelections: [] }
    });
    expect(
      result.appendedEvents[0].type === 'visualization.preference-recorded'
        ? result.appendedEvents[0].payload.displaySetId
        : 'unexpected'
    ).toBeUndefined();
  });

  it('records a preference for the initial view when a presentation has no checkpoints', async () => {
    const repository = new MemoryProjectRepository();
    const presentations = [randomUUID(), randomUUID()] as [string, string];
    const document = comparisonDocument(randomUUID(), randomUUID(), presentations, []);
    await repository.create(document, 'owner');
    const projectService = {
      repository,
      compiler: {} as ProjectServiceDependencies['compiler'],
      readDslRevision: vi.fn()
    };

    const result = await recordProjectPreference(
      {
        projectId: document.projectId,
        expectedHead: document.events.length,
        presentations,
        preferred: presentations[0],
        step: 0,
        visualSelections: [],
        operationId: randomUUID()
      },
      { repository, projectService }
    );

    expect(result.appendedEvents[0]).toMatchObject({
      type: 'visualization.preference-recorded',
      payload: { presentations, preferred: presentations[0], step: 0, visualSelections: [] }
    });
  });

  it('validates and retains focused elements from both compared presentations', async () => {
    const repository = new MemoryProjectRepository();
    const presentations = [randomUUID(), randomUUID()] as [string, string];
    const document = comparisonDocument(randomUUID(), randomUUID(), presentations);
    await repository.create(document, 'owner');
    const projectService = {
      repository,
      compiler: {} as ProjectServiceDependencies['compiler'],
      readDslRevision: vi.fn()
    };
    const visualSelections = [
      { presentationEvent: 3, step: 0, instances: [0] },
      { presentationEvent: 4, step: 0, instances: [0] }
    ];

    const result = await recordProjectPreference(
      {
        projectId: document.projectId,
        expectedHead: document.events.length,
        presentations,
        preferred: presentations[0],
        step: 0,
        visualSelections,
        operationId: randomUUID()
      },
      { repository, projectService }
    );

    expect(result.appendedEvents[0]).toMatchObject({
      type: 'visualization.preference-recorded',
      payload: { visualSelections }
    });
  });

  it('rejects preference focus from a different visualization step', async () => {
    const repository = new MemoryProjectRepository();
    const presentations = [randomUUID(), randomUUID()] as [string, string];
    const document = comparisonDocument(randomUUID(), randomUUID(), presentations);
    await repository.create(document, 'owner');
    const projectService = {
      repository,
      compiler: {} as ProjectServiceDependencies['compiler'],
      readDslRevision: vi.fn()
    };

    await expect(
      recordProjectPreference(
        {
          projectId: document.projectId,
          expectedHead: document.events.length,
          presentations,
          preferred: presentations[0],
          step: 0,
          visualSelections: [{ presentationEvent: 3, step: 1, instances: [0] }],
          operationId: randomUUID()
        },
        { repository, projectService }
      )
    ).rejects.toThrow('unknown visualization step');
  });
});

function comparisonDocument(
  projectId: string,
  displaySetId: string | [string, string],
  presentationIds: [string, string],
  steps: Array<{ label: string }> = [{ label: 'Only step' }]
): ProjectDocument {
  const operationId = randomUUID();
  const source = recordText('visualization source', 'text/x-sverlin');
  const render = recordText(
    JSON.stringify({
      irVersion: 1,
      seed: 1,
      sourcePath: 'Main.sverlin',
      coordinates: {
        systemName: 'sverlin-logical-y-down',
        systemOrigin: 'top-left',
        systemYAxis: 'down'
      },
      root: -1,
      resources: [],
      findings: [],
      variables: [],
      elements: [
        {
          id: -1,
          role: 'Canvas',
          box: {
            bounds: { rectX: 0, rectY: 0, rectWidth: 640, rectHeight: 360 },
            padding: { top: 0, right: 0, bottom: 0, left: 0 },
            margin: { top: 0, right: 0, bottom: 0, left: 0 }
          },
          children: [0],
          style: {},
          styleVariables: []
        },
        {
          id: 0,
          role: 'Value',
          box: {
            bounds: { rectX: 20, rectY: 20, rectWidth: 120, rectHeight: 40 },
            padding: { top: 0, right: 0, bottom: 0, left: 0 },
            margin: { top: 0, right: 0, bottom: 0, left: 0 }
          },
          children: [],
          content: { kind: 'legacyTextContent', textSource: 'Value' },
          style: {},
          styleVariables: []
        }
      ],
      steps: steps.map(({ label }) => ({ label, instances: [{ id: 0, elementId: 0 }] }))
    }),
    'application/json'
  );
  const base = {
    format: 'sverlin-ir-v1' as const,
    stepSignature: 'shared-step-signature',
    source,
    render
  };
  return {
    schemaVersion: 2,
    projectId,
    events: [
      {
        id: 1,
        type: 'project.created',
        actor: { kind: 'user' },
        operationId,
        createdAt: '2026-08-30T00:00:00.000Z',
        payload: {
          title: 'Comparison',
          entryArtifactId: 'dsl-main',
          assistantId: 'sverlin-assistant',
          creation: { templateId: 'blank', renderer: 'sverlin' }
        }
      },
      {
        id: 2,
        type: 'artifact.version-created',
        actor: { kind: 'system' },
        operationId,
        createdAt: '2026-08-30T00:00:01.000Z',
        payload: {
          origin: { kind: 'initial' },
          changes: [
            {
              operation: 'upsert',
              artifact: {
                artifactId: 'dsl-main',
                path: 'Main.sverlin',
                language: 'sverlin',
                content: source
              }
            }
          ]
        }
      },
      ...presentationIds.map((presentationId, slot) => ({
        id: slot + 3,
        type: 'visualization.presented' as const,
        actor: { kind: 'system' as const },
        operationId,
        createdAt: `2026-08-30T00:00:0${slot + 2}.000Z`,
        payload: {
          displaySetId: Array.isArray(displaySetId) ? displaySetId[slot] : displaySetId,
          slot: slot as 0 | 1,
          presentation: { ...base, presentationId, seed: slot + 1 }
        }
      }))
    ]
  };
}
