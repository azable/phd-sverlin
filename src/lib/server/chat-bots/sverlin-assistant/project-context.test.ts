import { describe, expect, it } from 'vitest';

import type { ProjectEvent, ProjectEventOf } from '$lib/shared/projects/events';
import type { ProjectDocument } from '$lib/shared/projects/model';

import {
  projectAiContext,
  projectAiTimelineEntry,
  projectConversationMessages
} from './project-context';

const operationId = '12345678-1234-4123-8123-123456789abc';
const hash = '0'.repeat(64);
const fontResourceId = `sha256-${'1'.repeat(64)}`;
const textRunResourceId = `sha256-${'2'.repeat(64)}`;

describe('AI project context projection', () => {
  it('derives conversation only from feedback and assistant responses', () => {
    const feedback: ProjectEventOf<'feedback.submitted'> = {
      ...base(1),
      type: 'feedback.submitted',
      actor: { kind: 'user' },
      payload: { content: [{ type: 'markdown', text: 'Make this clearer' }], focus: [] }
    };
    const compilation: ProjectEventOf<'compilation.requested'> = {
      ...base(2),
      type: 'compilation.requested',
      payload: {
        purpose: 'assistant-edit',
        input: 'assistant-candidate',
        source: recorded('secret source', 'text/x-sverlin'),
        sourceLabel: 'Main.sverlin',
        seed: 7,
        attempt: 1
      }
    };
    const response: ProjectEventOf<'assistant.responded'> = {
      ...base(3),
      type: 'assistant.responded',
      actor: { kind: 'assistant', botId: 'sverlin-assistant' },
      payload: { content: [{ type: 'markdown', text: 'Updated' }] }
    };

    expect(projectConversationMessages([feedback, compilation, response])).toEqual([
      { role: 'user', content: 'Make this clearer' },
      { role: 'assistant', content: 'Updated' }
    ]);
  });

  it('indexes raw audit bodies by hash and expands only selected events', () => {
    const request: ProjectEventOf<'ai.generation-requested'> = {
      ...base(3),
      type: 'ai.generation-requested',
      payload: {
        attempt: 1,
        purpose: 'initial',
        prompt: recorded('private prompt', 'application/json'),
        promptTemplateSha256: '1'.repeat(64),
        requestedModel: 'test-model',
        parameters: {}
      }
    };
    const document = projectDocument(request);

    expect(projectAiTimelineEntry(request).summary).not.toContain('private prompt');
    const compact = projectAiContext(document);
    expect(JSON.stringify(compact.timeline)).not.toContain('private prompt');
    expect(compact.currentWorkspace.artifacts[0].source).toBe('current source');
    expect(compact.selected.events).toEqual([]);
    expect(compact.selected.presentations).toEqual([]);

    const expanded = projectAiContext(document, { eventIds: [request.id] });
    expect(expanded.selected.events[0].event).toEqual(request);
    expect(JSON.stringify(expanded.selected.events[0])).toContain('private prompt');
  });

  it('exposes compiler findings globally and on the selected zero-based instance', () => {
    const request: ProjectEventOf<'ai.generation-requested'> = {
      ...base(3),
      type: 'ai.generation-requested',
      payload: {
        attempt: 1,
        purpose: 'initial',
        prompt: recorded('{}', 'application/json'),
        promptTemplateSha256: '1'.repeat(64),
        requestedModel: 'test-model',
        parameters: {}
      }
    };
    const document = projectDocument(request);
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
      findings: [
        {
          findingId: 'typography.size-reduced.0',
          findingSeverity: 'findingWarning',
          findingCode: 'typography.size-reduced',
          findingMessage: 'Text was made smaller.',
          findingElementIds: [0],
          findingStepIndices: [0],
          findingEvidence: []
        }
      ],
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
          children: [0, 1],
          style: {},
          styleVariables: []
        },
        {
          id: 0,
          role: 'Value',
          box: {
            bounds: { rectX: 0, rectY: 0, rectWidth: 100, rectHeight: 20 },
            padding: { top: 0, right: 0, bottom: 0, left: 0 },
            margin: { top: 0, right: 0, bottom: 0, left: 0 }
          },
          children: [],
          content: { kind: 'legacyTextContent', textSource: 'hello' },
          style: {},
          styleVariables: []
        },
        {
          id: 1,
          role: 'Value',
          box: {
            bounds: { rectX: 0, rectY: 30, rectWidth: 100, rectHeight: 20 },
            padding: { top: 0, right: 0, bottom: 0, left: 0 },
            margin: { top: 0, right: 0, bottom: 0, left: 0 }
          },
          children: [],
          content: { kind: 'legacyTextContent', textSource: 'world' },
          style: {},
          styleVariables: []
        }
      ],
      steps: [
        {
          label: 'show',
          instances: [
            { id: 0, elementId: 0 },
            { id: 1, elementId: 1 }
          ]
        }
      ]
    };
    document.events.push(
      event(4, 'visualization.presented', {
        displaySetId: '12345678-1234-4123-8123-123456789abd',
        slot: 0,
        presentation: {
          presentationId: '12345678-1234-4123-8123-123456789ac1',
          format: 'sverlin-ir-v1',
          stepSignature: 'show',
          seed: 2,
          source: recorded('current source', 'text/x-sverlin'),
          render: recorded(JSON.stringify(visualization), 'application/json')
        }
      })
    );
    const presented = projectAiContext(document, {
      eventIds: [],
      visualSelections: [
        { presentationEvent: 4, step: 0, instances: [0] },
        { presentationEvent: 4, step: 0, instances: [1] }
      ]
    });
    expect(presented.activeVisualizationFindings).toHaveLength(1);
    expect(presented.selected.visualizations[0]?.renderSummary).toMatchObject({ id: 4, seed: 2 });
    expect(presented.selected.visualizations[0]?.elements[0]).toMatchObject({
      instanceId: 0,
      findings: [{ findingCode: 'typography.size-reduced' }]
    });
    expect(presented.selected.visualizations[1]?.elements[0]).toMatchObject({
      instanceId: 1,
      findings: []
    });
  });

  it('supplies a preferred pair and retains observations for later preference decisions', () => {
    const request: ProjectEventOf<'ai.generation-requested'> = {
      ...base(3),
      type: 'ai.generation-requested',
      payload: {
        attempt: 1,
        purpose: 'initial',
        prompt: recorded('{}', 'application/json'),
        promptTemplateSha256: '1'.repeat(64),
        requestedModel: 'test-model',
        parameters: {}
      }
    };
    const document = projectDocument(request);
    const presentationIds = [
      '12345678-1234-4123-8123-123456789ac1',
      '12345678-1234-4123-8123-123456789ac2'
    ] as const;
    for (const [slot, presentationId] of presentationIds.entries()) {
      document.events.push(
        event(4 + slot, 'visualization.presented', {
          displaySetId: '12345678-1234-4123-8123-123456789abd',
          slot: slot as 0 | 1,
          presentation: {
            presentationId,
            format: 'sverlin-ir-v1',
            stepSignature: 'show',
            seed: slot + 1,
            source: recorded('current source', 'text/x-sverlin'),
            render: recorded(JSON.stringify(minimalVisualization(slot + 1)), 'application/json')
          }
        })
      );
    }
    document.events.push(
      event(6, 'visualization.preference-recorded', {
        displaySetId: '12345678-1234-4123-8123-123456789abd',
        presentations: [...presentationIds],
        preferred: presentationIds[0],
        step: 0,
        visualSelections: []
      }),
      {
        ...event(7, 'assistant.responded', {
          content: [{ type: 'markdown', text: 'The preference suggests clearer spacing.' }]
        }),
        actor: { kind: 'assistant', botId: 'sverlin-assistant' }
      }
    );

    const context = projectAiContext(document, {
      eventIds: [],
      presentationIds,
      interactionEventIds: [6]
    });

    expect(context.interaction).toEqual({
      kind: 'preference',
      eventId: 6,
      preferredPresentationId: presentationIds[0],
      alternativePresentationId: presentationIds[1],
      step: 0
    });
    expect(context.selected.presentations.map(({ presentationId }) => presentationId)).toEqual(
      presentationIds
    );
    expect(context.selected.presentations[0]).toMatchObject({
      presentationId: presentationIds[0],
      renderSummary: { seed: 1 },
      elements: expect.arrayContaining([
        expect.objectContaining({
          role: 'Canvas',
          box: expect.any(Object),
          style: expect.any(Object)
        }),
        expect.objectContaining({
          role: 'Value',
          content: {
            kind: 'plain',
            source: 'Value',
            fontFamily: 'Inter',
            fontWeight: 400,
            fontStyle: 'normal',
            fontSize: 16,
            alignment: 'center'
          }
        })
      ]),
      steps: [{ label: 'show', instances: [{ id: 0, elementId: 0 }] }]
    });
    const selectedJson = JSON.stringify(context.selected.presentations);
    expect(selectedJson).not.toContain('current source');
    expect(selectedJson).not.toContain('styleVariables');
    expect(selectedJson).not.toContain('variables');
    expect(selectedJson).not.toContain('fragmentClusters');
    expect(selectedJson).not.toContain('secret-variable');
    expect(selectedJson).not.toContain('layoutLines');
    expect(selectedJson).not.toContain(textRunResourceId);
    expect(projectConversationMessages(document.events)).toEqual([
      {
        role: 'user',
        content: `I preferred presentation ${presentationIds[0]} over the alternative in display set 12345678-1234-4123-8123-123456789abd at step 0.`
      },
      { role: 'assistant', content: 'The preference suggests clearer spacing.' }
    ]);
  });
});

function minimalVisualization(seed: number) {
  return {
    irVersion: 1,
    seed,
    sourcePath: 'Main.sverlin',
    coordinates: {
      systemName: 'sverlin-logical-y-down',
      systemOrigin: 'top-left',
      systemYAxis: 'down'
    },
    root: -1,
    resources: [
      {
        descriptorId: fontResourceId,
        descriptorKind: 'fontResource',
        descriptorSha256: '1'.repeat(64),
        descriptorMediaType: 'font/ttf',
        descriptorByteLength: 100
      },
      {
        descriptorId: textRunResourceId,
        descriptorKind: 'textRunResource',
        descriptorSha256: '2'.repeat(64),
        descriptorMediaType: 'application/x-sverlin-text-run',
        descriptorByteLength: 50
      }
    ],
    findings: [],
    variables: [{ id: 'secret-variable', value: { kind: 'number', value: 42 } }],
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
        content: {
          kind: 'plainTextContent',
          textLayout: {
            layoutSource: 'Value',
            layoutWhitespace: 'textPreserveWhitespace',
            layoutWrapMode: { kind: 'textNoAutomaticWrap' },
            layoutFont: {
              instanceFamily: 'Inter',
              instanceResourceId: fontResourceId,
              instanceWeight: 400,
              instanceStyle: 'normal',
              instanceAxes: [],
              instanceFeatures: []
            },
            layoutFontSize: 16,
            layoutPreferredSize: 16,
            layoutLineHeight: 20,
            layoutDirection: 'textLeftToRight',
            layoutScript: 'Latn',
            layoutLanguage: 'und',
            layoutAlignment: 'center',
            layoutContentBox: { rectX: 20, rectY: 20, rectWidth: 120, rectHeight: 40 },
            layoutLines: [
              {
                lineSourceRange: { sourceRangeStart: 0, sourceRangeEnd: 5 },
                lineDisplayText: 'Value',
                lineOriginX: 40,
                lineBaselineY: 45,
                lineAdvance: 50,
                lineInkBounds: { rectX: 40, rectY: 30, rectWidth: 50, rectHeight: 16 }
              }
            ],
            layoutTextRunResource: textRunResourceId
          }
        },
        style: {},
        styleVariables: [{ field: 'fontSize', variables: ['secret-variable'] }]
      }
    ],
    steps: [{ label: 'show', instances: [{ id: 0, elementId: 0 }] }]
  };
}

function projectDocument(request: ProjectEventOf<'ai.generation-requested'>): ProjectDocument {
  return {
    schemaVersion: 2,
    projectId: 'project-test',
    events: [
      event(1, 'project.created', {
        title: 'Test',
        entryArtifactId: 'dsl-main',
        assistantId: 'sverlin-assistant',
        creation: { templateId: 'blank' }
      }),
      event(2, 'artifact.version-created', {
        origin: { kind: 'initial' },
        changes: [
          {
            operation: 'upsert',
            artifact: {
              artifactId: 'dsl-main',
              path: 'Main.sverlin',
              language: 'sverlin',
              content: recorded('current source', 'text/x-sverlin')
            }
          }
        ]
      }),
      request
    ]
  };
}

function recorded(text: string, mediaType: string) {
  return { text, sha256: hash, mediaType };
}

function base(id: number) {
  return {
    id,
    operationId,
    actor: { kind: 'system' as const },
    createdAt: `2026-01-01T00:00:0${id}.000Z`
  };
}

function event<Type extends ProjectEvent['type']>(
  id: number,
  type: Type,
  payload: ProjectEventOf<Type>['payload']
): ProjectEventOf<Type> {
  return { ...base(id), type, payload } as ProjectEventOf<Type>;
}
