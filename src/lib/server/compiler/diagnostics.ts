/**
 * Parsing, classification, and display of Haskell compiler failures.
 *
 * @packageDocumentation
 */

import type { CompilerDiagnostic } from '$lib/shared/projects/events/values';

import type { CompileDebug, CompileFailureKind } from './compile';

const ansiEscape = new RegExp(`${String.fromCharCode(27)}\\[[0-9;]*m`, 'g');
const diagnosticHeader = /^(.+?):(\d+):(\d+):\s+(error|warning):(?:\s+\[([^\]]+)\])?\s*$/;

/** Parse GHC-style stderr into structured compiler diagnostics. */
export function parseCompilerDiagnostics(stderr: string): CompilerDiagnostic[] {
  const normalized = stderr.replace(ansiEscape, '').trim();
  if (!normalized) return [];

  const lines = normalized.split(/\r?\n/);
  const diagnostics: CompilerDiagnostic[] = [];
  let start = -1;
  let header: RegExpMatchArray | null = null;

  function finish(end: number) {
    if (start < 0 || header === null) return;

    const raw = lines.slice(start, end).join('\n').trim();
    const message = lines
      .slice(start + 1, end)
      .map((line) => line.trim())
      .filter(Boolean)
      .join('\n');

    diagnostics.push({
      severity: header[4] as 'error' | 'warning',
      ...(header[5] ? { code: header[5] } : {}),
      sourcePath: header[1],
      line: Number(header[2]),
      column: Number(header[3]),
      message: message || raw,
      raw
    });
  }

  for (let index = 0; index < lines.length; index += 1) {
    const nextHeader = lines[index].match(diagnosticHeader);
    if (!nextHeader) continue;

    finish(index);
    start = index;
    header = nextHeader;
  }

  finish(lines.length);

  return diagnostics.length > 0
    ? diagnostics
    : [{ severity: 'unknown', message: normalized, raw: normalized }];
}

/** Classify a failed compiler run for repair and user-facing behavior. */
export function classifyCompileFailure(debug: CompileDebug): CompileFailureKind {
  if (debug.error === 'Compile backend was cancelled.') return 'cancelled';
  if (debug.timedOut) return 'timeout';
  if (debug.error || debug.stderr.includes('[sverlin:build-failed]')) return 'infrastructure';

  const diagnostics = parseCompilerDiagnostics(debug.stderr);
  if (diagnostics.some((diagnostic) => diagnostic.sourcePath !== undefined)) return 'source';

  return 'pipeline';
}

/** Format structured diagnostics as a compact human-readable summary. */
export function formatDiagnosticSummary(diagnostics: CompilerDiagnostic[]): string {
  if (diagnostics.length === 0) return 'The compiler did not provide a diagnostic.';

  return diagnostics
    .map((diagnostic) => {
      const location =
        diagnostic.sourcePath && diagnostic.line && diagnostic.column
          ? `${diagnostic.sourcePath}:${diagnostic.line}:${diagnostic.column}`
          : diagnostic.sourcePath;
      const code = diagnostic.code ? ` [${diagnostic.code}]` : '';
      return `${location ? `${location}: ` : ''}${diagnostic.severity}${code}\n${diagnostic.message}`;
    })
    .join('\n\n');
}
