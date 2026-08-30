import { beforeEach, describe, expect, it, vi } from 'vitest';

import { projectHead, projectSnapshotAt } from '$lib/shared/projects/projection';

import type { ProjectCommandDependencies } from './commands';
import { MemoryProjectRepository } from './memory-repository.test-support';
import type { ProjectServiceDependencies } from './service';

const mocks = vi.hoisted(() => ({
  compileSource: vi.fn(),
  preparePrompt: vi.fn(),
  generatePrepared: vi.fn()
}));

vi.mock('$lib/server/chat-bots/registry', () => ({
  getChatbot: () => ({
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

  const repository = new MemoryProjectRepository();
  serviceDependencies = {
    repository,
    compiler: {
      generate: mocks.compileSource,
      generateBatch: vi.fn(),
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
        creation: { templateId: template.id }
      }
    });
    expect(snapshot.creation).toEqual({ templateId: template.id });
    expect(snapshot.artifacts[snapshot.entryArtifactId].content.text).toBe(template.source);
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
});

describe('submitProjectFeedback', () => {
  it('records both failed candidates and stops after one explicit repair', async () => {
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject({ title: 'Finite repair' }, serviceDependencies);
    const operationId = '12345678-1234-4123-8123-123456789abc';

    const result = await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        text: 'Change the visualization',
        focus: [],
        seed: 7,
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
    expect(projectSnapshotAt(result.document).activeRender?.payload.seed).toBe(
      projectSnapshotAt(created).activeRender?.payload.seed
    );
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
        text: 'Create a visualization',
        focus: [],
        seed: 7,
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

  it('resolves focused history into historical source and render context', async () => {
    mocks.generatePrepared.mockReset().mockResolvedValue({
      reply: 'No source change needed.',
      prompt: {},
      generation: { botId: 'ai-assistant', adapterId: 'test-adapter', model: 'test-model' }
    });
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject({ title: 'Focused history' }, serviceDependencies);
    const render = projectSnapshotAt(created).activeRender!;

    await submitProjectFeedback(
      {
        projectId: created.projectId,
        expectedHead: projectHead(created).id,
        text: 'Use this as context',
        focus: [render.id],
        seed: 7,
        operationId: '12345678-1234-4123-8123-123456789abc'
      },
      commandDependencies
    );

    expect(mocks.preparePrompt).toHaveBeenCalledWith(
      expect.objectContaining({
        project: expect.objectContaining({
          selected: {
            events: [
              expect.objectContaining({
                event: expect.objectContaining({ id: render.id }),
                workspace: expect.objectContaining({
                  artifacts: [expect.objectContaining({ source: expect.any(String) })]
                }),
                activeRender: expect.objectContaining({
                  id: render.id,
                  seed: render.payload.seed,
                  renderSha256: render.payload.render.sha256
                })
              })
            ]
          }
        })
      })
    );
  });

  it('rejects a compact visual selection that does not exist in the render', async () => {
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject({ title: 'Selection validation' }, serviceDependencies);
    const render = projectSnapshotAt(created).activeRender!;

    await expect(
      submitProjectFeedback(
        {
          projectId: created.projectId,
          expectedHead: projectHead(created).id,
          focus: [],
          selection: {
            render: render.id,
            step: 99,
            instances: [1]
          },
          seed: 7,
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
    reply,
    sourceArtifactContent,
    prompt: {
      initialPrompt: 'test prompt',
      messages: [],
      context: {},
      parameters: { model: 'test-model' },
      responseFormat: { name: 'test', schema: {} }
    },
    generation: {
      botId: 'ai-assistant',
      adapterId: 'test-adapter',
      model: 'test-model'
    }
  };
}
