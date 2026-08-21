import { describe, expect, it } from 'vitest';

import {
  classifyCompileFailure,
  formatDiagnosticSummary,
  parseCompilerDiagnostics
} from './compiler-diagnostics';

describe('compiler diagnostics', () => {
  it('parses source-labelled multiline GHC diagnostics', () => {
    const diagnostics = parseCompilerDiagnostics(`Main.sverlin:10:3: error: [GHC-83865]
    • Couldn't match type ‘Destroy Message’ with ‘()’
      Expected: Choreography ()
      Actual: Choreography (Destroy Message)

Main.sverlin:18:7: warning: [GHC-12345]
    Unused binding`);

    expect(diagnostics).toEqual([
      expect.objectContaining({
        severity: 'error',
        code: 'GHC-83865',
        sourcePath: 'Main.sverlin',
        line: 10,
        column: 3,
        message: expect.stringContaining("Couldn't match type")
      }),
      expect.objectContaining({
        severity: 'warning',
        code: 'GHC-12345',
        line: 18,
        column: 7,
        message: 'Unused binding'
      })
    ]);
    expect(formatDiagnosticSummary(diagnostics)).toContain('Main.sverlin:10:3: error [GHC-83865]');
  });

  it('retains unrecognized compiler output as one diagnostic', () => {
    expect(parseCompilerDiagnostics('Solver failed to find a valid layout.')).toEqual([
      {
        severity: 'unknown',
        message: 'Solver failed to find a valid layout.',
        raw: 'Solver failed to find a valid layout.'
      }
    ]);
  });

  it('distinguishes source, infrastructure, timeout, and cancellation failures', () => {
    const debug = {
      command: 'compile-app',
      args: [],
      cwd: process.cwd(),
      durationMs: 1,
      exitCode: 1,
      stdout: '',
      stderr: 'Main.sverlin:1:1: error: [GHC-12345]\n    parse error'
    };

    expect(classifyCompileFailure(debug)).toBe('source');
    expect(classifyCompileFailure({ ...debug, stderr: '[sverlin:build-failed]' })).toBe(
      'infrastructure'
    );
    expect(classifyCompileFailure({ ...debug, timedOut: true })).toBe('timeout');
    expect(classifyCompileFailure({ ...debug, error: 'Compile backend was cancelled.' })).toBe(
      'cancelled'
    );
  });
});
