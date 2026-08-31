import { beforeEach, describe, expect, it, vi } from 'vitest';

import { projectHead, projectSnapshotAt } from '$lib/shared/projects/projection';
import { markdownMessage } from '$lib/shared/projects/events/message-content';
import type { ProjectEventOf } from '$lib/shared/projects/events';
import type { ProjectDocument } from '$lib/shared/projects/model';
import type { SverlinPresentation } from '$lib/shared/presentations';

import type { ProjectCommandDependencies } from './commands';
import { MemoryProjectRepository } from './memory-repository.test-support';
import { runWithProjectOperationSignal } from './operation-context';
import type { ProjectServiceDependencies } from './service';

const mocks = vi.hoisted(() => ({
  attemptProfiles: [
    {
      purpose: 'initial' as const,
      parameters: { model: 'gpt-5.6-luna', reasoningEffort: 'low' as const }
    },
    {
      purpose: 'repair' as const,
      parameters: { model: 'gpt-5.6-sol', reasoningEffort: 'medium' as const }
    },
    {
      purpose: 'repair' as const,
      parameters: { model: 'gpt-5.6-sol', reasoningEffort: 'high' as const }
    },
    {
      purpose: 'repair' as const,
      parameters: { model: 'gpt-5.6-sol', reasoningEffort: 'xhigh' as const }
    },
    {
      purpose: 'fallback' as const,
      parameters: { model: 'gpt-5.6-sol', reasoningEffort: 'xhigh' as const }
    }
  ],
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
    config: { attemptProfiles: mocks.attemptProfiles },
    preparePrompt: mocks.preparePrompt,
    generatePrepared: mocks.generatePrepared,
    requestTimeoutMs: () => 180_000
  }),
  getHtmlChatbot: () => ({
    config: { attemptProfiles: mocks.attemptProfiles },
    preparePrompt: mocks.preparePrompt,
    generatePrepared: mocks.generatePrepared,
    requestTimeoutMs: () => 180_000
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
        steps: [{ label: 'Initial view', instances: [{ id: 0, elementId: 0 }] }]
      }
    };
  });
  mocks.preparePrompt.mockReset().mockImplementation(async ({ attempt = 1 }) => {
    const profile = mocks.attemptProfiles[attempt - 1];
    return {
      initialPrompt: 'test prompt',
      messages: [],
      context: {},
      attempt: { number: attempt, purpose: profile?.purpose ?? 'repair' },
      parameters: profile?.parameters ?? { model: 'test-model' },
      responseFormat: { name: 'test', schema: {} }
    };
  });
  mocks.generatePrepared
    .mockReset()
    .mockImplementation(async (prompt) =>
      generation(
        `broken attempt ${prompt.attempt.number}`,
        `Candidate ${prompt.attempt.number}`,
        prompt.attempt.purpose === 'fallback'
          ? { struggledWith: 'the requested layout', simplified: 'the layout and animation' }
          : undefined
      )
    );
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
        config: { attemptProfiles: mocks.attemptProfiles },
        preparePrompt: mocks.preparePrompt,
        generatePrepared: mocks.generatePrepared,
        requestTimeoutMs: () => 180_000
      }) as unknown as ReturnType<ProjectCommandDependencies['getChatbot']>,
    getHtmlChatbot: () =>
      ({
        config: { attemptProfiles: mocks.attemptProfiles },
        preparePrompt: mocks.preparePrompt,
        generatePrepared: mocks.generatePrepared,
        requestTimeoutMs: () => 180_000
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
  it('durably queues Sverlin feedback without making a model request', async () => {
    const { createProject } = await import('./service');
    const { queueProjectFeedback } = await import('./commands');
    const created = await createProject({ title: 'Queued feedback' }, serviceDependencies);
    const operationId = '12345678-1234-4123-8123-123456789abc';
    const accepted = await serviceDependencies.repository.append(
      created.projectId,
      projectHead(created).id,
      [
        {
          type: 'operation.accepted',
          actor: { kind: 'user' },
          operationId,
          createdAt: '2026-08-30T12:00:00.000Z',
          payload: { kind: 'feedback' }
        }
      ]
    );

    const result = await queueProjectFeedback(
      {
        projectId: created.projectId,
        operationId,
        content: markdownMessage('Move the label.'),
        focus: [],
        presentationCount: 2,
        deadlineAt: '2026-08-30T12:05:00.000Z'
      },
      commandDependencies
    );

    expect(result.appendedEvents.map(({ type }) => type)).toEqual([
      'feedback.submitted',
      'assistant.turn-requested'
    ]);
    expect(result.appendedEvents[0]).toMatchObject({
      payload: { presentationCount: 2 }
    });
    expect(result.appendedEvents[1]).toMatchObject({
      payload: {
        interactionEventId: projectHead(accepted.document).id + 1,
        presentationCount: 2,
        deadlineAt: '2026-08-30T12:05:00.000Z'
      }
    });
    expect(mocks.generatePrepared).not.toHaveBeenCalled();
  });

  it('processes a claimed interaction and correlates the early assistant observation', async () => {
    const { createProject } = await import('./service');
    const { runQueuedSverlinAssistantTurn } = await import('./commands');
    const created = await createProject({ title: 'Claimed feedback' }, serviceDependencies);
    const feedbackOperationId = '12345678-1234-4123-8123-123456789abc';
    const assistantOperationId = '12345678-1234-4123-8123-123456789abd';
    const head = projectHead(created).id;
    const queued = await serviceDependencies.repository.append(created.projectId, head, [
      {
        type: 'feedback.submitted',
        actor: { kind: 'user' },
        operationId: feedbackOperationId,
        createdAt: '2026-08-30T12:00:00.000Z',
        payload: {
          content: markdownMessage('Explain the current layout.'),
          focus: [],
          presentationCount: 2
        }
      },
      {
        type: 'assistant.turn-requested',
        actor: { kind: 'system' },
        operationId: feedbackOperationId,
        createdAt: '2026-08-30T12:00:01.000Z',
        payload: { interactionEventId: head + 1, presentationCount: 2 }
      },
      {
        type: 'operation.accepted',
        actor: { kind: 'system' },
        operationId: assistantOperationId,
        createdAt: '2026-08-30T12:00:02.000Z',
        payload: { kind: 'assistant-turn' }
      },
      {
        type: 'assistant.turn-started',
        actor: { kind: 'system' },
        operationId: assistantOperationId,
        createdAt: '2026-08-30T12:00:03.000Z',
        payload: { requestEventIds: [head + 2], interactionEventIds: [head + 1] }
      }
    ]);
    mocks.generatePrepared.mockReset().mockResolvedValue(generation(undefined, 'I am looking.'));

    const result = await runQueuedSverlinAssistantTurn(
      { projectId: created.projectId, operationId: assistantOperationId },
      commandDependencies
    );

    expect(result.appendedEvents.map(({ type }) => type)).toEqual([
      'ai.generation-requested',
      'ai.generation-succeeded',
      'assistant.responded'
    ]);
    expect(result.appendedEvents.at(-1)).toMatchObject({
      payload: {
        content: markdownMessage('I am looking.'),
        inReplyTo: [head + 1]
      }
    });
    expect(projectHead(queued.document).id).toBe(head + 4);
  });

  it('generates the first candidate pair from accepted blank-project source on request', async () => {
    mocks.generatePrepared.mockReset().mockResolvedValue({
      reply: markdownMessage('I am preparing two more options.'),
      action: 'resample',
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
    expect(result.appendedEvents.find(({ type }) => type === 'assistant.responded')).toMatchObject({
      type: 'assistant.responded',
      payload: {
        content: markdownMessage('I am preparing two more options.')
      }
    });
  });

  it('keeps the visible candidate until a complete resampled pair is ready', async () => {
    mocks.generatePrepared.mockReset().mockResolvedValue({
      reply: markdownMessage('I am preparing another pair.'),
      action: 'resample',
      prompt: {},
      generation: { botId: 'sverlin-assistant', adapterId: 'test-adapter', model: 'test-model' }
    });
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject(
      { title: 'Pinned resample', creation: { templateId: 'linear-search' } },
      serviceDependencies
    );

    const result = await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        content: markdownMessage('Generate more visualizations.'),
        focus: [],
        presentationCount: 2,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );

    const firstReplacement = result.appendedEvents.findIndex(
      ({ type }) => type === 'visualization.presented'
    );
    const consumed = result.appendedEvents.findIndex(
      ({ type }) => type === 'visualization.candidates-advanced'
    );
    expect(firstReplacement).toBeGreaterThanOrEqual(0);
    expect(consumed).toBeGreaterThan(firstReplacement);
    expect(
      result.appendedEvents.filter(({ type }) => type === 'visualization.presented')
    ).toHaveLength(2);
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

  it('uses the fifth attempt for a simpler working fallback and explains it', async () => {
    mocks.generatePrepared.mockReset().mockImplementation(async (prompt) =>
      prompt.attempt.purpose === 'fallback'
        ? generation('valid simplified source', 'Here is the working version.', {
            struggledWith: 'combining every requested animation',
            simplified: 'the animation sequence while preserving the algorithm'
          })
        : generation(`broken attempt ${prompt.attempt.number}`, 'Trying the full design')
    );
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject({ title: 'Graceful fallback' }, serviceDependencies);

    const result = await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        content: markdownMessage('Make an elaborate animated visualization'),
        focus: [],
        presentationCount: 1,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );

    const requests = result.appendedEvents.filter(
      (event) => event.type === 'ai.generation-requested'
    );
    expect(requests.map(({ payload }) => payload.purpose)).toEqual([
      'initial',
      'repair',
      'repair',
      'repair',
      'fallback'
    ]);
    expect(requests.map(({ payload }) => payload.parameters.reasoningEffort)).toEqual([
      'low',
      'medium',
      'high',
      'xhigh',
      'xhigh'
    ]);
    expect(mocks.preparePrompt.mock.calls[4][0].compilationFeedback).toMatchObject({
      attempt: 4,
      priorFailureSummaries: expect.arrayContaining([
        expect.stringContaining('Attempt 1'),
        expect.stringContaining('Attempt 4')
      ])
    });
    expect(
      mocks.generateBatch.mock.calls.every(
        ([request]) =>
          JSON.stringify(request.seeds) ===
          JSON.stringify(mocks.generateBatch.mock.calls[0][0].seeds)
      )
    ).toBe(true);
    expect(result.appendedEvents.at(-1)).toMatchObject({
      type: 'assistant.responded',
      payload: {
        content: [
          expect.objectContaining({
            type: 'markdown',
            text: expect.stringContaining('combining every requested animation')
          }),
          { type: 'markdown', text: 'Here is the working version.' }
        ]
      }
    });
    expect(result.appendedEvents.some(({ type }) => type === 'artifact.version-created')).toBe(
      true
    );
  });

  it('records a focused preference and defers source revision with a brief observation', async () => {
    const { submitProjectPreference } = await import('./commands');
    const comparison = await createComparisonProject('Preference observation');
    mocks.generatePrepared
      .mockReset()
      .mockResolvedValue(generation(undefined, 'The preference suggests clearer spacing.'));
    const visualSelections = comparison.presentations.map(({ id }) => ({
      presentationEvent: id,
      step: 0,
      instances: [0]
    }));

    const result = await submitProjectPreference(
      {
        projectId: comparison.document.projectId,
        expectedHead: projectHead(comparison.document).id,
        presentations: comparison.presentations.map(
          ({ payload }) => payload.presentation.presentationId
        ) as [string, string],
        preferred: comparison.presentations[0].payload.presentation.presentationId,
        step: 0,
        visualSelections,
        operationId: '12345678-1234-4123-8123-123456789abd'
      },
      commandDependencies
    );

    expect(result.appendedEvents[0]).toMatchObject({
      type: 'visualization.preference-recorded',
      payload: { visualSelections }
    });
    expect(result.appendedEvents.at(-1)).toMatchObject({
      type: 'assistant.responded',
      payload: { content: markdownMessage('The preference suggests clearer spacing.') }
    });
    expect(result.appendedEvents.some(({ type }) => type === 'artifact.version-created')).toBe(
      false
    );
    expect(mocks.generateBatch).toHaveBeenCalledTimes(1);
    expect(mocks.preparePrompt.mock.calls.at(-1)?.[0].project).toMatchObject({
      interaction: {
        kind: 'preference',
        preferredPresentationId: comparison.presentations[0].payload.presentation.presentationId,
        alternativePresentationId: comparison.presentations[1].payload.presentation.presentationId,
        step: 0
      },
      selected: {
        presentations: [
          { eventId: comparison.presentations[0].id },
          { eventId: comparison.presentations[1].id }
        ],
        visualizations: [
          { presentationEvent: comparison.presentations[0].id, elements: [{ instanceId: 0 }] },
          { presentationEvent: comparison.presentations[1].id, elements: [{ instanceId: 0 }] }
        ]
      }
    });
  });

  it('proactively compiles a revised pair when preference evidence is sufficient', async () => {
    const { submitProjectPreference } = await import('./commands');
    const comparison = await createComparisonProject('Preference adaptation');
    mocks.generatePrepared
      .mockReset()
      .mockResolvedValue(generation('valid adapted source', 'I adapted the spacing.'));

    const result = await submitProjectPreference(
      {
        projectId: comparison.document.projectId,
        expectedHead: projectHead(comparison.document).id,
        presentations: comparison.presentations.map(
          ({ payload }) => payload.presentation.presentationId
        ) as [string, string],
        preferred: comparison.presentations[1].payload.presentation.presentationId,
        step: 0,
        visualSelections: [],
        operationId: '12345678-1234-4123-8123-123456789abe'
      },
      commandDependencies
    );

    expect(
      result.appendedEvents.filter(({ type }) => type === 'visualization.presented')
    ).toHaveLength(2);
    expect(result.appendedEvents).toContainEqual(
      expect.objectContaining({ type: 'artifact.version-created' })
    );
    const observationIndex = result.appendedEvents.findIndex(
      ({ type }) => type === 'assistant.responded'
    );
    const compilationIndex = result.appendedEvents.findIndex(
      ({ type }) => type === 'compilation.requested'
    );
    expect(observationIndex).toBeGreaterThanOrEqual(0);
    expect(observationIndex).toBeLessThan(compilationIndex);
    expect(result.appendedEvents[observationIndex]).toMatchObject({
      type: 'assistant.responded',
      payload: { content: markdownMessage('I adapted the spacing.') }
    });
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

  it('uses the shared fifth-attempt fallback for repeatedly unsafe HTML', async () => {
    mocks.generatePrepared.mockReset().mockImplementation(async (prompt) =>
      prompt.attempt.purpose === 'fallback'
        ? htmlGeneration(manifest('<main>Simple and safe</main>'), 'Simplified result', {
            struggledWith: 'the interactive controls',
            simplified: 'the interaction into static explanatory frames'
          })
        : htmlGeneration(manifest('<script>alert(1)</script>'), 'Unsafe attempt')
    );
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
        content: markdownMessage('Create an interactive explanation'),
        focus: [],
        presentationCount: 1,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );

    expect(mocks.generatePrepared).toHaveBeenCalledTimes(5);
    expect(
      result.appendedEvents.filter(({ type }) => type === 'ai.generation-requested').at(-1)
    ).toMatchObject({ payload: { purpose: 'fallback', attempt: 5 } });
    expect(result.appendedEvents.at(-1)).toMatchObject({
      type: 'assistant.responded',
      payload: {
        content: [
          expect.objectContaining({ type: 'markdown', text: expect.stringContaining('controls') }),
          { type: 'markdown', text: 'Simplified result' }
        ]
      }
    });
  });

  it('records four failed repairs and one failed simplification before stopping', async () => {
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

    expect(mocks.generatePrepared).toHaveBeenCalledTimes(5);
    expect(
      result.appendedEvents.filter(({ type }) => type === 'ai.generation-requested')
    ).toHaveLength(5);
    expect(result.appendedEvents.filter(({ type }) => type === 'compilation.failed')).toHaveLength(
      5
    );
    expect(result.appendedEvents.at(-1)).toMatchObject({
      type: 'system.notified',
      payload: { severity: 'error' }
    });
    expect(result.appendedEvents.every((event) => event.operationId === operationId)).toBe(true);
    const revisionEvents = result.appendedEvents.filter(
      (event) => event.type === 'ai.generation-requested' || event.type === 'compilation.requested'
    );
    expect(revisionEvents).toHaveLength(10);
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

  it('does not start a repair without one complete provider timeout before the deadline', async () => {
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject({ title: 'Deadline repair' }, serviceDependencies);
    const controller = new AbortController();

    const result = await runWithProjectOperationSignal(
      controller.signal,
      () =>
        submitProjectFeedback(
          {
            projectId: created.projectId,
            expectedHead: projectHead(created).id,
            content: markdownMessage('Change the visualization'),
            focus: [],
            presentationCount: 1,
            operationId: '12345678-1234-4123-8123-123456789abc'
          },
          commandDependencies
        ),
      Date.now() + 179_000
    );

    expect(mocks.generatePrepared).toHaveBeenCalledTimes(1);
    expect(result.appendedEvents.at(-1)).toMatchObject({
      type: 'system.notified',
      payload: { message: expect.stringContaining('not enough time left') }
    });
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
      action: 'respond',
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

  it('retains valid assistant-authored element references for granular questions', async () => {
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject(
      { title: 'Assistant element reference', creation: { templateId: 'linear-search' } },
      serviceDependencies
    );
    const presentation = presentedEvent(created);
    const presentationId = presentation.payload.presentation.presentationId;
    mocks.generatePrepared.mockReset().mockResolvedValue({
      reply: [
        {
          type: 'element-ref',
          presentationId,
          presentationEvent: presentation.id,
          step: 0,
          instances: [0]
        },
        { type: 'markdown', text: 'Is this the part you prefer?' }
      ],
      action: 'respond',
      prompt: {},
      generation: { botId: 'sverlin-assistant', adapterId: 'test-adapter', model: 'test-model' }
    });

    const result = await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        content: markdownMessage('The preferred candidate feels clearer.'),
        focus: [],
        presentationCount: 2,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );

    expect(result.appendedEvents.at(-1)).toMatchObject({
      type: 'assistant.responded',
      payload: {
        content: expect.arrayContaining([expect.objectContaining({ type: 'element-ref' })])
      }
    });
  });

  it('turns a known presentation UUID in assistant Markdown into a retained reference', async () => {
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject(
      { title: 'Assistant presentation reference', creation: { templateId: 'linear-search' } },
      serviceDependencies
    );
    const presentationId = presentedEvent(created).payload.presentation.presentationId;
    mocks.generatePrepared.mockReset().mockResolvedValue({
      reply: markdownMessage(`I prefer presentation \`${presentationId}\` here.`),
      action: 'respond',
      prompt: {},
      generation: { botId: 'sverlin-assistant', adapterId: 'test-adapter', model: 'test-model' }
    });

    const result = await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        content: markdownMessage('Which treatment is clearer?'),
        focus: [],
        presentationCount: 2,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );

    expect(result.appendedEvents.at(-1)).toMatchObject({
      type: 'assistant.responded',
      payload: {
        content: [
          { type: 'markdown', text: 'I prefer presentation ' },
          { type: 'presentation-ref', presentationId },
          { type: 'markdown', text: ' here.' }
        ]
      }
    });
  });

  it('resolves focused history into historical source and render context', async () => {
    mocks.generatePrepared.mockReset().mockResolvedValue({
      reply: markdownMessage('No source change needed.'),
      action: 'respond',
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
      action: 'respond',
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

function generation(
  sourceArtifactContent: string | undefined,
  reply: string,
  recovery?: { struggledWith: string; simplified: string }
) {
  return {
    reply: markdownMessage(reply),
    action: sourceArtifactContent === undefined ? ('respond' as const) : ('revise' as const),
    sourceArtifactContent,
    ...(recovery ? { recovery } : {}),
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

async function createComparisonProject(title: string): Promise<{
  document: ProjectDocument;
  presentations: Array<
    Extract<ProjectDocument['events'][number], { type: 'visualization.presented' }>
  >;
}> {
  const { createProject } = await import('./service');
  const { submitProjectFeedback } = await import('./commands');
  const created = await createProject({ title }, serviceDependencies);
  mocks.generatePrepared
    .mockReset()
    .mockResolvedValue(generation('valid comparison source', 'Compare these candidates.'));
  const result = await submitProjectFeedback(
    {
      projectId: created.projectId,
      expectedHead: projectHead(created).id,
      content: markdownMessage('Create a comparison'),
      focus: [],
      presentationCount: 2,
      operationId: '12345678-1234-4123-8123-123456789abc'
    },
    commandDependencies
  );
  return {
    document: result.document,
    presentations: result.appendedEvents.filter(
      (
        event
      ): event is Extract<ProjectDocument['events'][number], { type: 'visualization.presented' }> =>
        event.type === 'visualization.presented'
    )
  };
}

function manifest(html: string) {
  return {
    format: 'sverlin-html-frames' as const,
    version: 1 as const,
    frames: [{ label: 'Overview', html }]
  };
}

function htmlGeneration(
  value: ReturnType<typeof manifest> | undefined,
  reply: string,
  recovery?: { struggledWith: string; simplified: string }
) {
  return {
    reply: markdownMessage(reply),
    candidates: value ? [{ label: 'Candidate', manifest: value }] : [],
    ...(recovery ? { recovery } : {}),
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
