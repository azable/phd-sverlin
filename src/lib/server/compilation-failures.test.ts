import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import {
  compilationFailureAttempt,
  createCompilationFailureRecord,
  persistCompilationFailureRecord,
  sourceSha256,
  updateCompilationFailureRecord
} from './compilation-failures';

let outputDirectory: string;
let previousOutputDirectory: string | undefined;

beforeEach(async () => {
  previousOutputDirectory = process.env.SVERLIN_OUTPUT_DIR;
  outputDirectory = await mkdtemp(path.join(tmpdir(), 'sverlin-failures-test-'));
  process.env.SVERLIN_OUTPUT_DIR = outputDirectory;
});

afterEach(async () => {
  if (previousOutputDirectory === undefined) {
    delete process.env.SVERLIN_OUTPUT_DIR;
  } else {
    process.env.SVERLIN_OUTPUT_DIR = previousOutputDirectory;
  }
  await rm(outputDirectory, { recursive: true, force: true });
});

describe('compilation failure records', () => {
  it('atomically stores a versioned record and its repaired resolution', async () => {
    const source = 'program = missing\n';
    const attempt = compilationFailureAttempt({
      attempt: 1,
      candidateContent: source,
      seed: 42,
      debug: {
        command: 'compile-app',
        args: [],
        cwd: process.cwd(),
        durationMs: 12,
        exitCode: 1,
        stdout: '',
        stderr: 'compile error'
      },
      failureKind: 'source',
      diagnostics: [{ severity: 'error', message: 'missing', raw: 'missing' }]
    });
    const initial = await createCompilationFailureRecord({
      origin: { kind: 'ai-candidate', turnId: 'turn-1', userMessage: 'change it' },
      artifact: {
        id: 'dsl-main',
        path: 'Main.sverlin',
        baseRevision: 0,
        baseContent: source,
        baseSha256: sourceSha256(source)
      },
      attempts: [attempt],
      resolution: 'retrying'
    });
    const recovered = updateCompilationFailureRecord(initial, { resolution: 'recovered' });
    const destination = await persistCompilationFailureRecord(recovered);
    const stored = JSON.parse(await readFile(destination, 'utf8'));

    expect(stored).toMatchObject({
      schemaVersion: 1,
      recordId: initial.recordId,
      resolution: 'recovered',
      attempts: [
        {
          attempt: 1,
          candidate: { content: source, sha256: sourceSha256(source) },
          compile: { seed: 42, failureKind: 'source' }
        }
      ]
    });
  });
});
