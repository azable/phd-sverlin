import { beforeEach, describe, expect, it, vi } from 'vitest';

const { generateOpenAIReply, OpenAIConfigurationError } = vi.hoisted(() => ({
  generateOpenAIReply: vi.fn(),
  OpenAIConfigurationError: class OpenAIConfigurationError extends Error {
    constructor() {
      super('OpenAI is not configured on the server.');
    }
  }
}));
const { compileSource, persistedFailureRecords } = vi.hoisted(() => ({
  compileSource: vi.fn(),
  persistedFailureRecords: [] as unknown[]
}));

vi.mock('$lib/server/chat-adapters/openai', () => ({
  generateOpenAIReply,
  OpenAIConfigurationError,
  openAIAdapter: {
    id: 'openai-responses',
    generateReply: generateOpenAIReply
  }
}));

vi.mock('$lib/server/openai-chat', () => ({ OpenAIConfigurationError }));
vi.mock('$lib/server/compile-visualization', () => ({ compileSource }));
vi.mock('$lib/server/compilation-failures', async (importOriginal) => ({
  ...(await importOriginal<typeof import('$lib/server/compilation-failures')>()),
  safelyPersistCompilationFailureRecord: vi.fn(async (record: unknown) => {
    persistedFailureRecords.push(structuredClone(record));
  })
}));
import { DELETE, GET, POST } from './+server';
import { updateArtifactFromManualEdit } from '$lib/server/artifacts/service';
import { getArtifactSyncState } from '$lib/server/artifacts/store';

const compiledTrace = {
  canvas: { width: 800, height: 600 },
  elements: [],
  seed: 42,
  sourcePath: 'Main.sverlin',
  steps: [],
  variables: []
};

const compileDebug = {
  command: 'compile-app',
  args: [],
  cwd: process.cwd(),
  durationMs: 10,
  exitCode: 0,
  stdout: '',
  stderr: ''
};

function post(body: unknown) {
  return POST({
    request: new Request('http://localhost/api/chat', {
      method: 'POST',
      body: JSON.stringify(body),
      headers: { 'content-type': 'application/json' }
    })
  } as Parameters<typeof POST>[0]);
}

describe('chat API', () => {
  beforeEach(async () => {
    vi.clearAllMocks();
    persistedFailureRecords.length = 0;
    generateOpenAIReply.mockResolvedValue({ reply: 'A helpful answer.' });
    compileSource.mockResolvedValue({ ok: true, trace: compiledTrace, debug: compileDebug });
    await DELETE({} as Parameters<typeof DELETE>[0]);
  });

  it('returns and stores a generated reply', async () => {
    const response = await post({ message: '  hello there  ' });

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      messages: [
        { role: 'assistant', content: 'Hi! Ask me anything about this workspace.' },
        { role: 'user', content: 'hello there' },
        { role: 'assistant', content: 'A helpful answer.' }
      ],
      artifact: {
        artifactId: 'dsl-main',
        current: {
          id: 'dsl-main',
          path: 'Main.sverlin',
          language: 'sverlin'
        },
        headRevision: 0,
        streamVersion: 0,
        events: []
      }
    });
    expect(generateOpenAIReply).toHaveBeenCalledWith(
      expect.objectContaining({
        messages: [
          { role: 'assistant', content: 'Hi! Ask me anything about this workspace.' },
          { role: 'user', content: 'hello there' }
        ],
        initialPrompt: expect.stringMatching(
          /visualization designer[\s\S]*Infer reasonable example data/
        ),
        context: expect.objectContaining({
          artifact: expect.any(Object),
          dslInterface: expect.stringMatching(
            /small representative input[\s\S]*blank artefact[\s\S]*seed as a compositional input[\s\S]*meaningful shared alignment[\s\S]*Every relation expression[\s\S]*ensure \$ right first =\| gap \|= left second[\s\S]*Create pending <- create @Item \(LInt 3\)[\s\S]*Selected item <- select @Item[\s\S]*FixedStyle TextAlignCenter[\s\S]*same type and semantic state should share a visual identity[\s\S]*shared family tokens[\s\S]*Selected active <- select @Item[\s\S]*Plain text is a first-class treatment[\s\S]*fixed dark foreground text colour[\s\S]*Different seeds produce visible variation[\s\S]*spatial variation budget[\s\S]*They need not break meaningful internal alignment[\s\S]*Variable border <- choice @BorderStyle/
          )
        }),
        parameters: {
          model: 'gpt-5.6',
          reasoningEffort: 'medium',
          maxOutputTokens: 4096
        },
        responseFormat: expect.objectContaining({ name: 'chat_result', strict: true })
      })
    );
    expect(compileSource).not.toHaveBeenCalled();

    const history = await GET({} as Parameters<typeof GET>[0]);
    await expect(history.json()).resolves.toMatchObject({
      messages: expect.arrayContaining([{ role: 'assistant', content: 'A helpful answer.' }])
    });
  });

  it.each([
    ['blank message', { message: '   ' }],
    ['missing message', {}],
    ['non-string message', { message: 42 }]
  ])('rejects a %s', async (_label, body) => {
    const response = await post(body);

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: '`message` must be a non-empty string.'
    });
  });

  it('rejects an invalid visualization seed before calling the provider', async () => {
    const response = await post({ message: 'hello', seed: 0 });

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: 'Seed must be a positive integer that JavaScript can represent safely.'
    });
    expect(generateOpenAIReply).not.toHaveBeenCalled();
  });

  it('rejects malformed JSON', async () => {
    const response = await POST({
      request: new Request('http://localhost/api/chat', {
        method: 'POST',
        body: '{',
        headers: { 'content-type': 'application/json' }
      })
    } as Parameters<typeof POST>[0]);

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: 'Request body must be valid JSON.'
    });
  });

  it('reports missing server configuration without saving the user message', async () => {
    generateOpenAIReply.mockRejectedValue(new OpenAIConfigurationError());

    const response = await post({ message: 'hello' });

    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toEqual({
      error: 'OpenAI is not configured on the server.'
    });
    const history = await GET({} as Parameters<typeof GET>[0]);
    await expect(history.json()).resolves.toMatchObject({
      messages: [{ role: 'assistant', content: 'Hi! Ask me anything about this workspace.' }]
    });
  });

  it('sanitizes provider failures', async () => {
    generateOpenAIReply.mockRejectedValue(new Error('secret provider details'));

    const response = await post({ message: 'hello' });

    expect(response.status).toBe(502);
    await expect(response.json()).resolves.toEqual({
      error: 'The chat service is unavailable.'
    });
  });

  it('resets the current transcript', async () => {
    await post({ message: 'hello' });

    const response = await DELETE({} as Parameters<typeof DELETE>[0]);

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      messages: [{ role: 'assistant', content: 'Hi! Ask me anything about this workspace.' }],
      artifact: { headRevision: 0, streamVersion: 0, events: [] }
    });
  });

  it('tracks a generated source revision and patch', async () => {
    const source =
      'program :: Choreography ()\nprogram = return ()\n\nvisualization :: VisualizationBuilder ()\nvisualization = return ()\n\n-- generated update\n';
    generateOpenAIReply.mockResolvedValue({
      reply: 'Updated the DSL.',
      sourceArtifactContent: source
    });

    const response = await post({ message: 'simplify the DSL', seed: 42 });

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      artifact: {
        current: { content: source },
        headRevision: 1,
        streamVersion: 1,
        events: [{ revision: 1, patch: [{ op: 'replace', path: '/content', value: source }] }]
      },
      compiledVisualization: { seed: 42, revision: 1, trace: compiledTrace }
    });
    expect(compileSource).toHaveBeenCalledWith(
      expect.objectContaining({
        sourceContent: source,
        sourceLabel: 'Main.sverlin',
        seed: 42,
        owner: 'ai-candidate'
      })
    );
  });

  it('repairs one failed candidate internally before committing', async () => {
    const invalidSource = 'program = missing\n';
    const repairedSource =
      'program :: Choreography ()\nprogram = return ()\n\nvisualization :: VisualizationBuilder ()\nvisualization = return ()\n\n-- repaired update\n';
    generateOpenAIReply
      .mockResolvedValueOnce({ reply: 'First attempt.', sourceArtifactContent: invalidSource })
      .mockResolvedValueOnce({ reply: 'Corrected.', sourceArtifactContent: repairedSource });
    compileSource
      .mockResolvedValueOnce({
        ok: false,
        error: 'Compile backend exited with code 1.',
        status: 500,
        failureKind: 'source',
        diagnostics: [
          {
            severity: 'error',
            code: 'GHC-88464',
            sourcePath: 'Main.sverlin',
            line: 1,
            column: 11,
            message: 'Variable not in scope: missing',
            raw: 'Main.sverlin:1:11: error: [GHC-88464]'
          }
        ],
        debug: { ...compileDebug, exitCode: 1, stderr: 'compile error' }
      })
      .mockResolvedValueOnce({ ok: true, trace: compiledTrace, debug: compileDebug });

    const response = await post({ message: 'change it', seed: 42 });
    const state = await response.json();

    expect(response.status).toBe(200);
    expect(state.artifact.current.content).toBe(repairedSource);
    expect(state.artifact.events.at(-1).after.content).toBe(repairedSource);
    expect(state.compiledVisualization).toMatchObject({ seed: 42, trace: compiledTrace });
    expect(generateOpenAIReply).toHaveBeenCalledTimes(2);
    expect(generateOpenAIReply.mock.calls[1]?.[0].context.compilationFeedback).toMatchObject({
      failedSource: invalidSource,
      diagnostics: [expect.objectContaining({ code: 'GHC-88464' })]
    });
    expect(persistedFailureRecords.at(-1)).toMatchObject({
      schemaVersion: 1,
      resolution: 'recovered',
      prompt: {
        botId: 'ai-assistant',
        messages: expect.arrayContaining([{ role: 'user', content: 'change it' }]),
        parameters: expect.objectContaining({ model: 'gpt-5.6' })
      },
      repairPrompt: {
        context: {
          compilationFeedback: expect.objectContaining({ failedSource: invalidSource })
        }
      },
      attempts: [expect.objectContaining({ attempt: 1 })]
    });
  });

  it('keeps the current artifact when both candidates fail', async () => {
    const before = await GET({} as Parameters<typeof GET>[0]);
    const beforeState = await before.json();
    generateOpenAIReply
      .mockResolvedValueOnce({ reply: 'First attempt.', sourceArtifactContent: 'first failure' })
      .mockResolvedValueOnce({ reply: 'Second attempt.', sourceArtifactContent: 'second failure' });
    compileSource.mockResolvedValue({
      ok: false,
      error: 'Compile backend exited with code 1.',
      status: 500,
      failureKind: 'source',
      diagnostics: [
        {
          severity: 'error',
          sourcePath: 'Main.sverlin',
          line: 1,
          column: 1,
          message: 'parse error',
          raw: 'Main.sverlin:1:1: error: parse error'
        }
      ],
      debug: { ...compileDebug, exitCode: 1, stderr: 'parse error' }
    });

    const response = await post({ message: 'break it', seed: 42 });
    const state = await response.json();

    expect(response.status).toBe(200);
    expect(state.artifact.headRevision).toBe(beforeState.artifact.headRevision);
    expect(state.artifact.current.content).toBe(beforeState.artifact.current.content);
    expect(state.messages.at(-1).content).toContain(
      'previous source and visualization are unchanged'
    );
    expect(state.compiledVisualization).toBeUndefined();
    expect(persistedFailureRecords.at(-1)).toMatchObject({
      resolution: 'rejected',
      attempts: [expect.objectContaining({ attempt: 1 }), expect.objectContaining({ attempt: 2 })]
    });
  });

  it('does not ask the assistant to repair an infrastructure failure', async () => {
    const source = 'program = return ()\nvisualization = return ()\n';
    generateOpenAIReply.mockResolvedValue({ reply: 'Updated.', sourceArtifactContent: source });
    compileSource.mockResolvedValue({
      ok: false,
      error: 'Cabal could not start.',
      status: 500,
      failureKind: 'infrastructure',
      diagnostics: [{ severity: 'unknown', message: 'Cabal could not start.', raw: 'failed' }],
      debug: { ...compileDebug, exitCode: 1, stderr: '[sverlin:build-failed]' }
    });

    const response = await post({ message: 'change it', seed: 42 });

    expect(response.status).toBe(502);
    expect(generateOpenAIReply).toHaveBeenCalledTimes(1);
    expect(persistedFailureRecords.at(-1)).toMatchObject({
      resolution: 'infrastructure-failure',
      attempts: [expect.objectContaining({ attempt: 1 })]
    });
  });

  it('does not commit a compiled candidate over a newer artifact revision', async () => {
    const candidate = 'program = return ()\nvisualization = return ()\n';
    generateOpenAIReply.mockResolvedValue({ reply: 'Updated.', sourceArtifactContent: candidate });
    compileSource.mockImplementationOnce(async () => {
      const artifact = getArtifactSyncState();
      await updateArtifactFromManualEdit(
        `${artifact.current.content}\n-- concurrent edit`,
        artifact.headRevision,
        'concurrent test edit'
      );
      return { ok: true, trace: compiledTrace, debug: compileDebug };
    });

    const response = await post({ message: 'change it', seed: 42 });

    expect(response.status).toBe(409);
    expect(getArtifactSyncState().current.content).toContain('-- concurrent edit');
    expect(getArtifactSyncState().current.content).not.toBe(candidate);
  });

  it('passes the complete artifact history to the next chatbot turn', async () => {
    const before = await GET({} as Parameters<typeof GET>[0]);
    const beforeState = await before.json();
    const existingEvents = beforeState.artifact.events.length;

    for (let revision = 1; revision <= 6; revision += 1) {
      const source = `program :: Choreography ()\nprogram = return ()\n\nvisualization :: VisualizationBuilder ()\nvisualization = return ()\n-- revision ${revision}\n`;
      generateOpenAIReply.mockResolvedValueOnce({
        reply: `Revision ${revision}`,
        sourceArtifactContent: source
      });
      await post({ message: `apply revision ${revision}`, seed: 42 });
    }

    generateOpenAIReply.mockResolvedValueOnce({ reply: 'History is available.' });
    await post({ message: 'summarize the history' });

    const historyRequest = generateOpenAIReply.mock.calls.at(-1)?.[0];
    expect(historyRequest.context.artifact.history).toHaveLength(existingEvents + 6);
    expect(historyRequest.context.artifact.history.at(-1).after.content).toContain('-- revision 6');

    const reset = await DELETE({} as Parameters<typeof DELETE>[0]);
    await expect(reset.json()).resolves.toMatchObject({
      artifact: {
        headRevision: existingEvents + 7,
        events: expect.arrayContaining([
          expect.objectContaining({
            revision: existingEvents + 7,
            source: expect.objectContaining({ reason: 'reset' })
          })
        ])
      }
    });
  });
});
