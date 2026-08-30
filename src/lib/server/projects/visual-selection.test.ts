import { describe, expect, it } from 'vitest';

import type { ProjectDocument } from '$lib/shared/projects/model';

import { resolveProjectVisualSelection } from './visual-selection';

describe('project visual selection resolution', () => {
  it('resolves instances from a current visualization presentation', () => {
    const document = presentationDocument();

    const resolved = resolveProjectVisualSelection(document, {
      presentationEvent: 2,
      step: 0,
      instances: [0, 0]
    });

    expect(resolved.selection).toEqual({ presentationEvent: 2, step: 0, instances: [0] });
    expect(resolved.step.label).toBe('Overview');
    expect(resolved.sourceSha256).toBe('a'.repeat(64));
  });

  it('rejects instances not present in the selected presentation step', () => {
    expect(() =>
      resolveProjectVisualSelection(presentationDocument(), {
        presentationEvent: 2,
        step: 0,
        instances: [9]
      })
    ).toThrow('unknown render instance');
  });
});

function presentationDocument(): ProjectDocument {
  const visualization = {
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
          bounds: { rectX: 0, rectY: 0, rectWidth: 100, rectHeight: 80 },
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
          bounds: { rectX: 0, rectY: 0, rectWidth: 20, rectHeight: 20 },
          padding: { top: 0, right: 0, bottom: 0, left: 0 },
          margin: { top: 0, right: 0, bottom: 0, left: 0 }
        },
        children: [],
        style: {},
        styleVariables: []
      }
    ],
    steps: [{ label: 'Overview', instances: [{ id: 0, elementId: 0 }] }]
  };
  return {
    schemaVersion: 1,
    projectId: 'project-test',
    events: [
      {
        id: 1,
        type: 'project.created',
        actor: { kind: 'user' },
        operationId: '12345678-1234-4123-8123-123456789abc',
        createdAt: '2026-08-30T00:00:01.000Z',
        payload: { title: 'Test', entryArtifactId: 'dsl-main' }
      },
      {
        id: 2,
        type: 'visualization.presented',
        actor: { kind: 'system' },
        operationId: '12345678-1234-4123-8123-123456789abc',
        createdAt: '2026-08-30T00:00:02.000Z',
        payload: {
          displaySetId: '12345678-1234-4123-8123-123456789abd',
          slot: 0,
          presentation: {
            presentationId: '12345678-1234-4123-8123-123456789ac1',
            format: 'sverlin-ir-v1',
            stepSignature: 'overview',
            seed: 1,
            source: { text: 'source', sha256: 'a'.repeat(64), mediaType: 'text/x-sverlin' },
            render: {
              text: JSON.stringify(visualization),
              sha256: 'b'.repeat(64),
              mediaType: 'application/json'
            }
          }
        }
      }
    ]
  };
}
