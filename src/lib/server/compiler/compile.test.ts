import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, describe, expect, it } from 'vitest';

import type { Visualization } from '$lib/shared/visualization';

import { compileCommand, readCompileBundle, runCompile } from './compile';

const temporaryRoots: string[] = [];

afterEach(async () => {
  await Promise.all(
    temporaryRoots.splice(0).map((root) => rm(root, { recursive: true, force: true }))
  );
});

describe('runCompile', () => {
  it('streams stdout and stderr chunks while the command runs', async () => {
    const stdoutChunks: string[] = [];
    const stderrChunks: string[] = [];

    const result = await runCompile(
      '/bin/bash',
      ['-c', 'printf out; printf err >&2'],
      process.cwd(),
      1_000,
      {
        onStdout: (chunk) => {
          stdoutChunks.push(chunk);
        },
        onStderr: (chunk) => {
          stderrChunks.push(chunk);
        }
      }
    );

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe('out');
    expect(result.stderr).toBe('err');
    expect(stdoutChunks.join('')).toBe('out');
    expect(stderrChunks.join('')).toBe('err');
  });

  it('settles when a timed-out shell command leaves child processes behind', async () => {
    const startedAt = Date.now();
    const result = await runCompile('/bin/bash', ['-c', 'sleep 10 & wait'], process.cwd(), 100);

    expect(result.timedOut).toBe(true);
    expect(result.exitCode).toBe(null);
    expect(result.timeoutMs).toBe(100);
    expect(Date.now() - startedAt).toBeLessThan(3_000);
  });

  it('uses SVERLIN_COMPILE_TIMEOUT_MS when no explicit timeout is provided', async () => {
    const previousTimeout = process.env.SVERLIN_COMPILE_TIMEOUT_MS;
    process.env.SVERLIN_COMPILE_TIMEOUT_MS = '100';

    try {
      const result = await runCompile('/bin/bash', ['-c', 'sleep 10 & wait'], process.cwd());

      expect(result.timedOut).toBe(true);
      expect(result.timeoutMs).toBe(100);
    } finally {
      if (previousTimeout === undefined) {
        delete process.env.SVERLIN_COMPILE_TIMEOUT_MS;
      } else {
        process.env.SVERLIN_COMPILE_TIMEOUT_MS = previousTimeout;
      }
    }
  });
});

describe('compileSource', () => {
  it('passes an isolated source snapshot and its canonical label to the compiler', () => {
    const command = compileCommand(
      42,
      '/tmp/request-a/compiled.json',
      '/tmp/request-a/source/Main.sverlin',
      'Main.sverlin'
    );

    expect(command.command).toBe('node');
    expect(command.args.slice(0, 2)).toEqual(['scripts/run-compile.mjs', '--']);
    expect(command.args).toEqual(
      expect.arrayContaining([
        '--source',
        '/tmp/request-a/source/Main.sverlin',
        '--source-label',
        'Main.sverlin'
      ])
    );
  });

  it('accepts only manifest attachments matching the IR, path, size, and digest', async () => {
    const root = await mkdtemp(path.join(tmpdir(), 'sverlin-compile-package-'));
    temporaryRoots.push(root);
    const outputPath = path.join(root, 'compiled.json');
    const bytes = new TextEncoder().encode('font payload');
    const sha256 = digest(bytes);
    const id = `sha256-${sha256}`;
    const visualization = emptyVisualization();
    visualization.resources.push({
      descriptorId: id,
      descriptorKind: 'fontResource',
      descriptorSha256: sha256,
      descriptorMediaType: 'font/ttf',
      descriptorByteLength: bytes.byteLength
    });
    const compiledJson = JSON.stringify(visualization);
    await mkdir(path.join(root, 'resources'));
    await writeFile(outputPath, compiledJson);
    await writeFile(path.join(root, 'resources', id), bytes);
    await writeFile(
      `${outputPath}.manifest.json`,
      JSON.stringify(manifest(compiledJson, id, sha256, bytes.byteLength))
    );

    const result = await readCompileBundle(outputPath, compiledJson, visualization);
    expect(result.resources).toHaveLength(1);
    expect(result.resources[0]).toMatchObject({ id, sha256, byteLength: bytes.byteLength });
    expect(result.targetDiagnostics).toEqual([
      { severity: 'warning', code: 'target.test', message: 'Target warning' }
    ]);

    await writeFile(path.join(root, 'resources', id), 'tampered');
    await expect(readCompileBundle(outputPath, compiledJson, visualization)).rejects.toThrow(
      /byte length|SHA-256/
    );
  });
});

function emptyVisualization(): Visualization {
  return {
    irVersion: 1,
    seed: 1,
    sourcePath: 'Main.sverlin',
    coordinates: {
      systemName: 'sverlin-css96-y-down',
      systemUnitsPerInch: 96,
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
  };
}

function manifest(compiledJson: string, id: string, sha256: string, byteLength: number) {
  return {
    manifestVersion: 1,
    primary: {
      relativePath: 'compiled.json',
      mediaType: 'application/json',
      sha256: digest(new TextEncoder().encode(compiledJson)),
      byteLength: Buffer.byteLength(compiledJson)
    },
    attachments: [
      {
        relativePath: `resources/${id}`,
        mediaType: 'font/ttf',
        sha256,
        byteLength
      }
    ],
    diagnostics: [{ severity: 'warning', code: 'target.test', message: 'Target warning' }],
    provenance: {
      packageVersion: 1,
      textRunFormatVersion: 2,
      shapingEngine: 'harfbuzz',
      shapingEngineVersion: 'test',
      fontCatalogSha256: null
    }
  };
}

function digest(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex');
}
