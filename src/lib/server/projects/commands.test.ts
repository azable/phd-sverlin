import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { projectAt } from '$lib/projects/project';

const mocks = vi.hoisted(() => ({
  compileSource: vi.fn(),
  preparePrompt: vi.fn(),
  generatePrepared: vi.fn()
}));

vi.mock('$lib/server/compile-visualization', () => ({ compileSource: mocks.compileSource }));
vi.mock('$lib/server/chat-bots/registry', () => ({
  getChatbot: () => ({
    preparePrompt: mocks.preparePrompt,
    generatePrepared: mocks.generatePrepared
  })
}));
vi.mock('./fingerprints', () => ({
  readDslApiFingerprint: vi.fn(async () => 'f'.repeat(64)),
  sourceSha256: (_value: string) => 'e'.repeat(64)
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
      trace: {
        seed,
        sourcePath: 'Main.sverlin',
        canvas: { width: 640, height: 360 },
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
    const correlationId = '12345678-1234-4123-8123-123456789abc';

    const result = await submitProjectFeedback({
      projectId: created.document.projectId,
      expectedHeadEventId: created.headEventId,
      text: 'Change the visualization',
      seed: 7,
      correlationId
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
    expect(result.appendedEvents.every((event) => event.correlationId === correlationId)).toBe(
      true
    );
    expect(
      result.document.events.filter(({ type }) => type === 'artifact.version-created')
    ).toHaveLength(1);
    expect(projectAt(result.document).activeRender?.payload.seed).toBe(
      created.snapshot.activeRender?.payload.seed
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
    const { projectRepository } = await import('./repository');
    const created = await createProject('Provider audit');

    const result = await submitProjectFeedback({
      projectId: created.document.projectId,
      expectedHeadEventId: created.headEventId,
      text: 'Create a visualization',
      seed: 7
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
    const details = JSON.parse(
      await projectRepository.readTextBlob(created.document.projectId, failed.payload.details)
    );
    expect(details.providerResponse).toEqual(providerResponse);
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
