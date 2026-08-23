import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { projectHead, projectSnapshotAt } from '$lib/shared/projects/projection';

const mocks = vi.hoisted(() => ({
  compileSource: vi.fn(),
  preparePrompt: vi.fn(),
  generatePrepared: vi.fn()
}));

vi.mock('$lib/server/compiler/compile', () => ({ compileSource: mocks.compileSource }));
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

let projectRoot: string;

beforeEach(async () => {
  vi.resetModules();
  mocks.compileSource.mockReset().mockImplementation(async ({ seed, sourceContent }) => {
    const debug = {
      command: 'test-compiler',
      args: [],
      cwd: process.cwd(),
      durationMs: 5,
      exitCode: sourceContent.startsWith('broken') ? 1 : 0,
      stdout: '',
      stderr: sourceContent.startsWith('broken') ? 'Main.sverlin:1:1: error: broken' : ''
    };
    if (sourceContent.startsWith('broken')) {
      return {
        ok: false,
        error: 'Compile backend exited with code 1.',
        debug,
        status: 500,
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
      debug,
      resources: [],
      targetDiagnostics: [],
      provenance: {
        packageVersion: 1,
        textRunFormatVersion: 2,
        shapingEngine: 'test',
        shapingEngineVersion: '1'
      },
      visualization: {
        irVersion: 3,
        seed,
        sourcePath: 'Main.sverlin',
        coordinates: {
          systemName: 'sverlin-css96-y-down',
          systemUnitsPerInch: 96,
          systemOrigin: 'top-left',
          systemYAxis: 'down'
        },
        canvas: { width: 640, height: 360 },
        resources: [],
        findings: [],
        variables: [],
        elements: [],
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

  projectRoot = await mkdtemp(path.join(tmpdir(), 'sverlin-command-test-'));
  process.env.SVERLIN_PROJECT_DIR = projectRoot;
});

afterEach(async () => {
  delete process.env.SVERLIN_PROJECT_DIR;
  await rm(projectRoot, { recursive: true, force: true });
});

describe('submitProjectFeedback', () => {
  it('records both failed candidates and stops after one explicit repair', async () => {
    const { createProject } = await import('./service');
    const { submitProjectFeedback } = await import('./commands');
    const created = await createProject('Finite repair');
    const operationId = '12345678-1234-4123-8123-123456789abc';

    const result = await submitProjectFeedback({
      projectId: created.projectId,
      expectedHead: projectHead(created).id,
      text: 'Change the visualization',
      focus: [],
      seed: 7,
      operationId
    });

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
    const created = await createProject('Provider audit');

    const result = await submitProjectFeedback({
      projectId: created.projectId,
      expectedHead: projectHead(created).id,
      text: 'Create a visualization',
      focus: [],
      seed: 7,
      operationId: '12345678-1234-4123-8123-123456789abc'
    });
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
    const created = await createProject('Focused history');
    const render = projectSnapshotAt(created).activeRender!;

    await submitProjectFeedback({
      projectId: created.projectId,
      expectedHead: projectHead(created).id,
      text: 'Use this as context',
      focus: [render.id],
      seed: 7,
      operationId: '12345678-1234-4123-8123-123456789abc'
    });

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
    const created = await createProject('Selection validation');
    const render = projectSnapshotAt(created).activeRender!;

    await expect(
      submitProjectFeedback({
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
      })
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
