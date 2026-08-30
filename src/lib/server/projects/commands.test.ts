import { beforeEach, describe, expect, it, vi } from 'vitest';

import { projectHead, projectSnapshotAt } from '$lib/shared/projects/projection';
import { markdownMessage } from '$lib/shared/projects/events/message-content';
import type { ProjectEventOf } from '$lib/shared/projects/events';
import type { ProjectDocument } from '$lib/shared/projects/model';
import type { SverlinPresentation } from '$lib/shared/presentations';

import type { ProjectCommandDependencies } from './commands';
import { MemoryProjectRepository } from './memory-repository.test-support';
import type { ProjectServiceDependencies } from './service';

const mocks = vi.hoisted(() => ({
  compileSource: vi.fn(),
  generateBatch: vi.fn(),
  preparePrompt: vi.fn(),
  generatePrepared: vi.fn()
}));

vi.mock('$lib/server/chat-bots/registry', () => ({
  assistantIntroduction: (assistantId: string) => ({
    botId: assistantId,
    text: 'Tell me what you would like to visualize.'
  }),
  getChatbot: () => ({
    preparePrompt: mocks.preparePrompt,
    generatePrepared: mocks.generatePrepared
  }),
  getHtmlChatbot: () => ({
    preparePrompt: mocks.preparePrompt,
    generatePrepared: mocks.generatePrepared
  })
}));
vi.mock('./fingerprints', () => ({
  readDslRevision: vi.fn(async () => ({
    contentSha256: 'f'.repeat(64),
    repositoryCommit: 'a'.repeat(40),
    workingTree: 'clean'
  })),
  sourceSha256: (_value: string) => 'e'.repeat(64),
  recordText: (text: string, mediaType: string) => ({
    text,
    mediaType,
    sha256: 'e'.repeat(64)
  })
}));

let serviceDependencies: ProjectServiceDependencies;
let commandDependencies: ProjectCommandDependencies;

beforeEach(() => {
  mocks.compileSource.mockReset().mockImplementation(async ({ seed, source }) => {
    const execution = {
      durationMs: 5,
      exitCode: source.content.startsWith('broken') ? 1 : 0,
      stdout: '',
      stderr: source.content.startsWith('broken') ? 'Main.sverlin:1:1: error: broken' : '',
      timedOut: false
    };
    if (source.content.startsWith('broken')) {
      return {
        ok: false,
        seed,
        error: 'Compile backend exited with code 1.',
        execution,
        failureKind: 'source',
        diagnostics: [
          {
            severity: 'error',
            sourcePath: 'Main.sverlin',
            line: 1,
            column: 1,
            message: 'broken',
            raw: 'Main.sverlin:1:1: error: broken'
          }
        ]
      };
    }
    return {
      ok: true,
      seed,
      execution,
      resources: [],
      targetDiagnostics: [],
      provenance: {
        packageVersion: 1,
        textRunFormatVersion: 2,
        shapingEngine: 'test',
        shapingEngineVersion: '1'
      },
      visualization: {
        irVersion: 1,
        seed,
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
            children: [],
            style: {},
            styleVariables: []
          }
        ],
        steps: []
      }
    };
  });
  mocks.preparePrompt.mockReset().mockResolvedValue({
    initialPrompt: 'test prompt',
    messages: [],
    context: {},
    parameters: { model: 'test-model' },
    responseFormat: { name: 'test', schema: {} }
  });
  mocks.generatePrepared
    .mockReset()
    .mockResolvedValueOnce(generation('broken first', 'First candidate'))
    .mockResolvedValueOnce(generation('broken repair', 'Repair candidate'));
  mocks.generateBatch
    .mockReset()
    .mockImplementation(async ({ source, seeds, signal }) =>
      Promise.all(seeds.map((seed: number) => mocks.compileSource({ source, seed, signal })))
    );

  const repository = new MemoryProjectRepository();
  serviceDependencies = {
    repository,
    compiler: {
      generate: mocks.compileSource,
      generateBatch: mocks.generateBatch,
      readiness: vi.fn(),
      status: vi.fn(),
      shutdown: vi.fn()
    },
    readDslRevision: vi.fn(async () => ({
      contentSha256: 'f'.repeat(64),
      repositoryCommit: 'a'.repeat(40),
      workingTree: 'clean' as const
    }))
  };
  commandDependencies = {
    repository,
    projectService: serviceDependencies,
    getChatbot: () =>
      ({
        preparePrompt: mocks.preparePrompt,
        generatePrepared: mocks.generatePrepared
      }) as unknown as ReturnType<ProjectCommandDependencies['getChatbot']>,
    getHtmlChatbot: () =>
      ({
        preparePrompt: mocks.preparePrompt,
        generatePrepared: mocks.generatePrepared
      }) as unknown as ReturnType<ProjectCommandDependencies['getHtmlChatbot']>,
    readDslRevision: serviceDependencies.readDslRevision
  };
});

describe('createProject', () => {
  it('copies an exact example, records its creation profile, and chooses a valid seed', async () => {
    const { getProjectTemplate } = await import('./starter-catalog');
    const { createProject } = await import('./service');
    const template = getProjectTemplate('linear-search');

    const created = await createProject(
      { creation: { templateId: template.id } },
      serviceDependencies
    );
    const snapshot = projectSnapshotAt(created);

    expect(created.events[0]).toMatchObject({
      type: 'project.created',
      payload: {
        title: template.title,
        assistantId: 'sverlin-assistant',
        creation: { templateId: template.id }
      }
    });
    expect(snapshot.assistantId).toBe('sverlin-assistant');
    expect(snapshot.creation).toEqual({ templateId: template.id });
    expect(snapshot.artifacts[snapshot.entryArtifactId].content.text).toBe(template.source);
    expect(created.events.some(({ type }) => type === 'assistant.responded')).toBe(false);
    expect(mocks.compileSource).toHaveBeenCalledWith(
      expect.objectContaining({
        source: expect.objectContaining({ content: template.source }),
        seed: expect.any(Number)
      })
    );
    const seed = mocks.compileSource.mock.calls[0][0].seed as number;
    expect(Number.isSafeInteger(seed)).toBe(true);
    expect(seed).toBeGreaterThan(0);
  });

  it('adds the selected assistant introduction to blank projects without a model request', async () => {
    const { createProject } = await import('./service');

    const created = await createProject(
      { creation: { templateId: 'blank', renderer: 'html' } },
      serviceDependencies
    );

    expect(created.events[0]).toMatchObject({
      type: 'project.created',
      payload: { assistantId: 'html-assistant' }
    });
    expect(created.events[2]).toMatchObject({
      type: 'assistant.responded',
      actor: { kind: 'assistant', botId: 'html-assistant' },
      payload: { content: markdownMessage('Tell me what you would like to visualize.') }
    });
    expect(mocks.generatePrepared).not.toHaveBeenCalled();
  });
});

describe('presentation buffer refill', () => {
  it('does not compile the untouched blank-project source', async () => {
    const { createProject, replenishProjectPresentations } = await import('./service');
    const created = await createProject(
      { title: 'Untouched blank', creation: { templateId: 'blank' } },
      serviceDependencies
    );
    mocks.generateBatch.mockClear();

    const unchanged = await replenishProjectPresentations(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        target: 4,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      serviceDependencies
    );

    expect(unchanged.appendedEvents).toEqual([]);
    expect(mocks.generateBatch).not.toHaveBeenCalled();
  });

  it('fills the exact current-source deficit and becomes idempotent at the target', async () => {
    const { createProject, replenishProjectPresentations } = await import('./service');
    const created = await createProject(
      {
        title: 'Buffered comparison',
        creation: { templateId: 'linear-search' },
        presentationCount: 2
      },
      serviceDependencies
    );
    mocks.generateBatch.mockClear();

    const filled = await replenishProjectPresentations(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        target: 4,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      serviceDependencies
    );

    expect(
      filled.appendedEvents.filter(({ type }) => type === 'visualization.presented')
    ).toHaveLength(2);
    expect(mocks.generateBatch).toHaveBeenCalledTimes(1);
    const unchanged = await replenishProjectPresentations(
      {
        projectId: created.projectId,
        expectedHead: projectHead(filled.document).id,
        target: 4,
        operationId: '22345678-1234-4234-8234-123456789abc'
      },
      serviceDependencies
    );
    expect(unchanged.appendedEvents).toEqual([]);
    expect(mocks.generateBatch).toHaveBeenCalledTimes(1);
  });
});

describe('submitProjectFeedback', () => {
  it('generates the first candidate pair from accepted blank-project source on request', async () => {
    mocks.generatePrepared.mockReset().mockResolvedValue({
      reply: [
        { type: 'markdown', text: 'Here are two options:' },
        { type: 'candidate-ref', slot: 0 },
        { type: 'candidate-ref', slot: 1 }
      ],
      candidateAction: 'generate',
      prompt: {},
      generation: { botId: 'sverlin-assistant', adapterId: 'test-adapter', model: 'test-model' }
    });
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject({ title: 'First candidates' }, serviceDependencies);

    const result = await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        content: markdownMessage('Show the accepted source'),
        focus: [],
        presentationCount: 2,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );

    const presented = result.appendedEvents.filter(
      (event) => event.type === 'visualization.presented'
    );
    expect(presented).toHaveLength(2);
    expect(
      result.appendedEvents.some((event) => event.type === 'visualization.candidates-advanced')
    ).toBe(false);
    expect(result.appendedEvents.at(-1)).toMatchObject({
      type: 'assistant.responded',
      payload: {
        content: [
          { type: 'markdown', text: 'Here are two options:' },
          {
            type: 'presentation-ref',
            presentationId: presented[0]?.payload.presentation.presentationId
          },
          {
            type: 'presentation-ref',
            presentationId: presented[1]?.payload.presentation.presentationId
          }
        ]
      }
    });
  });

  it('compiles a synchronized comparison directly from two distinct fresh seeds', async () => {
    mocks.generatePrepared.mockReset().mockResolvedValue(generation('valid source', 'Ready'));
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject({ title: 'Comparison' }, serviceDependencies);

    const result = await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        content: markdownMessage('Show two alternatives'),
        focus: [],
        presentationCount: 2,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );

    const request = mocks.generateBatch.mock.calls[0][0] as { seeds: number[] };
    expect(request.seeds).toHaveLength(2);
    expect(new Set(request.seeds).size).toBe(2);
    const presented = result.appendedEvents.filter(
      (event) => event.type === 'visualization.presented'
    );
    expect(presented).toHaveLength(2);
    expect(new Set(presented.map(({ payload }) => payload.displaySetId)).size).toBe(1);
    expect(new Set(presented.map(({ payload }) => payload.presentation.presentationId)).size).toBe(
      2
    );
  });

  it('repairs a partial batch once using the same two seeds', async () => {
    mocks.generatePrepared
      .mockReset()
      .mockResolvedValueOnce(generation('first source', 'First'))
      .mockResolvedValueOnce(generation('repaired source', 'Repaired'));
    mocks.generateBatch
      .mockReset()
      .mockImplementationOnce(async ({ source, seeds, signal }) => [
        await mocks.compileSource({ source, seed: seeds[0], signal }),
        await mocks.compileSource({
          source: { ...source, content: 'broken partial' },
          seed: seeds[1],
          signal
        })
      ])
      .mockImplementationOnce(async ({ source, seeds, signal }) =>
        Promise.all(seeds.map((seed: number) => mocks.compileSource({ source, seed, signal })))
      );
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject({ title: 'Partial batch' }, serviceDependencies);

    const result = await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        content: markdownMessage('Refine this'),
        focus: [],
        presentationCount: 2,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );

    expect(mocks.generateBatch).toHaveBeenCalledTimes(2);
    expect(mocks.generateBatch.mock.calls[1][0].seeds).toEqual(
      mocks.generateBatch.mock.calls[0][0].seeds
    );
    expect(
      result.appendedEvents.filter((event) => event.type === 'visualization.presented')
    ).toHaveLength(2);
  });

  it('accepts one safe HTML manifest and links it to its generation event', async () => {
    mocks.generatePrepared
      .mockReset()
      .mockResolvedValue(htmlGeneration(manifest('<main><h1>Safe</h1></main>'), 'Created it'));
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject(
      { creation: { templateId: 'blank', renderer: 'html' } },
      serviceDependencies
    );

    const result = await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        content: markdownMessage('Create an HTML visualization'),
        focus: [],
        presentationCount: 1,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );

    const generation = result.appendedEvents.find(
      (event) => event.type === 'ai.generation-succeeded'
    );
    const presented = result.appendedEvents.find(
      (event) => event.type === 'visualization.presented'
    );
    expect(presented).toMatchObject({
      type: 'visualization.presented',
      payload: { presentation: { format: 'html-frames-v1', generationEventId: generation?.id } }
    });
    expect(
      result.appendedEvents.filter(({ type }) => type === 'artifact.version-created')
    ).toHaveLength(1);
  });

  it('keeps a conversational HTML reply without forcing a visualization change', async () => {
    mocks.generatePrepared.mockReset().mockResolvedValue(htmlGeneration(undefined, 'No change'));
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject(
      { creation: { templateId: 'blank', renderer: 'html' } },
      serviceDependencies
    );

    const result = await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        content: markdownMessage('Explain the current design'),
        focus: [],
        presentationCount: 1,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );

    expect(result.appendedEvents.at(-1)).toMatchObject({
      type: 'assistant.responded',
      payload: { content: markdownMessage('No change') }
    });
    expect(result.appendedEvents.some(({ type }) => type === 'visualization.presented')).toBe(
      false
    );
  });

  it('allows one correction for an unsafe HTML manifest', async () => {
    mocks.generatePrepared
      .mockReset()
      .mockResolvedValueOnce(htmlGeneration(manifest('<script>alert(1)</script>'), 'First'))
      .mockResolvedValueOnce(htmlGeneration(manifest('<main>Corrected</main>'), 'Corrected'));
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject(
      { creation: { templateId: 'blank', renderer: 'html' } },
      serviceDependencies
    );

    const result = await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        content: markdownMessage('Create it'),
        focus: [],
        presentationCount: 1,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );

    expect(mocks.generatePrepared).toHaveBeenCalledTimes(2);
    expect(
      result.appendedEvents.filter(({ type }) => type === 'ai.generation-requested')
    ).toHaveLength(2);
    expect(result.appendedEvents.some(({ type }) => type === 'visualization.presented')).toBe(true);
  });

  it('records both failed candidates and stops after one explicit repair', async () => {
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject({ title: 'Finite repair' }, serviceDependencies);
    const operationId = '12345678-1234-4123-8123-123456789abc';

    const result = await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        content: markdownMessage('Change the visualization'),
        focus: [],
        presentationCount: 1,
        operationId
      },
      commandDependencies
    );

    expect(mocks.generatePrepared).toHaveBeenCalledTimes(2);
    expect(
      result.appendedEvents.filter(({ type }) => type === 'ai.generation-requested')
    ).toHaveLength(2);
    expect(result.appendedEvents.filter(({ type }) => type === 'compilation.failed')).toHaveLength(
      2
    );
    expect(result.appendedEvents.at(-1)).toMatchObject({
      type: 'system.notified',
      payload: { severity: 'error' }
    });
    expect(result.appendedEvents.every((event) => event.operationId === operationId)).toBe(true);
    const revisionEvents = result.appendedEvents.filter(
      (event) => event.type === 'ai.generation-requested' || event.type === 'compilation.requested'
    );
    expect(revisionEvents).toHaveLength(4);
    expect(
      revisionEvents.every(
        (event) =>
          event.payload.dslRevision?.contentSha256 === 'f'.repeat(64) &&
          event.payload.dslRevision.repositoryCommit === 'a'.repeat(40) &&
          event.payload.dslRevision.workingTree === 'clean'
      )
    ).toBe(true);
    expect(
      result.document.events.filter(({ type }) => type === 'artifact.version-created')
    ).toHaveLength(1);
    expect(
      result.document.events.filter(({ type }) => type === 'visualization.presented')
    ).toHaveLength(0);
  });

  it('stores the raw provider response when structured output is incomplete', async () => {
    const providerResponse = {
      id: 'response-incomplete',
      status: 'incomplete',
      incomplete_details: { reason: 'max_output_tokens' },
      output: []
    };
    mocks.generatePrepared.mockReset().mockRejectedValue(
      Object.assign(new Error('The chatbot response was incomplete (max_output_tokens).'), {
        name: 'InvalidChatbotResponseError',
        providerResponse
      })
    );
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject({ title: 'Provider audit' }, serviceDependencies);

    const result = await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        content: markdownMessage('Create a visualization'),
        focus: [],
        presentationCount: 1,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );
    const failed = result.appendedEvents.find((event) => event.type === 'ai.generation-failed');

    expect(mocks.generatePrepared).toHaveBeenCalledTimes(1);
    expect(failed).toMatchObject({
      type: 'ai.generation-failed',
      payload: {
        failureKind: 'invalid-response',
        message: 'The chatbot response was incomplete (max_output_tokens).',
        details: { mediaType: 'application/json' }
      }
    });
    if (failed?.type !== 'ai.generation-failed' || !failed.payload.details) {
      throw new Error('Expected a recorded generation failure.');
    }
    const details = JSON.parse(failed.payload.details.text);
    expect(details.providerResponse).toEqual(providerResponse);
  });

  it('records invalid candidate references as generation failures before success', async () => {
    const providerResponse = { id: 'response-invalid-reference' };
    mocks.generatePrepared.mockReset().mockResolvedValue({
      reply: [{ type: 'candidate-ref', slot: 0 }],
      candidateAction: 'none',
      prompt: {},
      providerResponse,
      generation: { botId: 'sverlin-assistant', adapterId: 'test-adapter', model: 'test-model' }
    });
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject(
      { title: 'Invalid candidate reference', creation: { templateId: 'linear-search' } },
      serviceDependencies
    );

    const result = await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        content: markdownMessage('Explain it'),
        focus: [],
        presentationCount: 1,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );

    expect(result.appendedEvents.some(({ type }) => type === 'ai.generation-succeeded')).toBe(
      false
    );
    const failed = result.appendedEvents.find(({ type }) => type === 'ai.generation-failed');
    expect(failed).toMatchObject({
      type: 'ai.generation-failed',
      payload: {
        failureKind: 'invalid-response',
        message: 'The assistant referenced unavailable candidate slot 0.'
      }
    });
    if (failed?.type !== 'ai.generation-failed' || !failed.payload.details) {
      throw new Error('Expected invalid response details.');
    }
    expect(JSON.parse(failed.payload.details.text).providerResponse).toEqual(providerResponse);
  });

  it('resolves focused history into historical source and render context', async () => {
    mocks.generatePrepared.mockReset().mockResolvedValue({
      reply: markdownMessage('No source change needed.'),
      candidateAction: 'none',
      prompt: {},
      generation: { botId: 'sverlin-assistant', adapterId: 'test-adapter', model: 'test-model' }
    });
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject(
      { title: 'Focused history', creation: { templateId: 'linear-search' } },
      serviceDependencies
    );
    const presentation = presentedEvent(created);

    await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        content: markdownMessage('Use this as context'),
        focus: [presentation.id],
        presentationCount: 1,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );

    expect(mocks.preparePrompt).toHaveBeenCalledWith(
      expect.objectContaining({
        project: expect.objectContaining({
          selected: expect.objectContaining({
            events: [
              expect.objectContaining({
                event: expect.objectContaining({ id: presentation.id }),
                workspace: expect.objectContaining({
                  artifacts: [expect.objectContaining({ source: expect.any(String) })]
                }),
                activePresentations: [
                  expect.objectContaining({
                    id: presentation.id,
                    seed: presentation.payload.presentation.seed,
                    renderSha256: presentation.payload.presentation.render.sha256
                  })
                ]
              })
            ]
          })
        })
      })
    );
  });

  it('retains and expands the presentations visible when feedback was submitted', async () => {
    mocks.generatePrepared.mockReset().mockResolvedValue({
      reply: markdownMessage('Noted.'),
      candidateAction: 'none',
      prompt: {},
      generation: { botId: 'sverlin-assistant', adapterId: 'test-adapter', model: 'test-model' }
    });
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject(
      { title: 'Presentation context', creation: { templateId: 'linear-search' } },
      serviceDependencies
    );
    const presentation = presentedEvent(created);
    const presentationId = presentation.payload.presentation.presentationId;

    const result = await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        content: [
          ...markdownMessage('Use the version I am viewing'),
          { type: 'presentation-ref', presentationId }
        ],
        focus: [],
        presentationCount: 1,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );

    expect(result.appendedEvents[0]).toMatchObject({
      type: 'feedback.submitted',
      payload: {
        content: expect.arrayContaining([
          expect.objectContaining({ type: 'presentation-ref', presentationId })
        ])
      }
    });
    expect(mocks.preparePrompt).toHaveBeenCalledWith(
      expect.objectContaining({
        project: expect.objectContaining({
          selected: expect.objectContaining({
            presentations: [
              expect.objectContaining({
                eventId: presentation.id,
                presentation: expect.objectContaining({
                  presentationId,
                  seed: presentation.payload.presentation.seed
                })
              })
            ]
          })
        })
      })
    );
  });

  it('rejects an inline element reference that does not exist in the presentation', async () => {
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject(
      { title: 'Selection validation', creation: { templateId: 'linear-search' } },
      serviceDependencies
    );
    const presentation = presentedEvent(created);

    await expect(
      submitProjectFeedback(
        {
          projectId: created.projectId,
          expectedHead: projectHead(created).id,
          focus: [],
          content: [
            {
              type: 'element-ref',
              presentationId: presentation.payload.presentation.presentationId,
              presentationEvent: presentation.id,
              step: 99,
              instances: [1]
            }
          ],
          presentationCount: 1,
          operationId: '12345678-1234-4123-8123-123456789abc'
        },
        commandDependencies
      )
    ).rejects.toThrow('unknown visualization step');
    expect(mocks.generatePrepared).not.toHaveBeenCalled();
  });
});

function generation(sourceArtifactContent: string, reply: string) {
  return {
    reply: markdownMessage(reply),
    candidateAction: 'none' as const,
    sourceArtifactContent,
    prompt: {
      initialPrompt: 'test prompt',
      messages: [],
      context: {},
      parameters: { model: 'test-model' },
      responseFormat: { name: 'test', schema: {} }
    },
    generation: {
      botId: 'sverlin-assistant',
      adapterId: 'test-adapter',
      model: 'test-model'
    }
  };
}

function manifest(html: string) {
  return {
    format: 'sverlin-html-frames' as const,
    version: 1 as const,
    frames: [{ label: 'Overview', html }]
  };
}

function htmlGeneration(value: ReturnType<typeof manifest> | undefined, reply: string) {
  return {
    reply: markdownMessage(reply),
    candidates: value ? [{ label: 'Candidate', manifest: value }] : [],
    prompt: {
      initialPrompt: 'html test prompt',
      messages: [],
      context: {},
      parameters: { model: 'test-model' },
      responseFormat: { name: 'html-test', schema: {} }
    },
    generation: {
      botId: 'html-assistant',
      adapterId: 'test-adapter',
      model: 'test-model'
    }
  };
}

type SverlinPresentedEvent = Omit<ProjectEventOf<'visualization.presented'>, 'payload'> & {
  payload: Omit<ProjectEventOf<'visualization.presented'>['payload'], 'presentation'> & {
    presentation: SverlinPresentation;
  };
};

function presentedEvent(document: ProjectDocument): SverlinPresentedEvent {
  const event = document.events.findLast(
    (candidate) => candidate.type === 'visualization.presented'
  );
  if (
    event?.type !== 'visualization.presented' ||
    event.payload.presentation.format !== 'sverlin-ir-v1'
  ) {
    throw new Error('Expected a Sverlin presentation event.');
  }
  return event as SverlinPresentedEvent;
}
