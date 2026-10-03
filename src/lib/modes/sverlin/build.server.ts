/** Compile a single component once, then correlate each requested seeded browser view. */

import { compileSvelteComponent, InvalidSvelteSourceError } from './compile.server';
import type { ModeBuildResult } from '../server';

export async function buildBatch(
  source: string,
  seeds: readonly number[],
  signal?: AbortSignal
): Promise<ModeBuildResult[]> {
  const start = performance.now();
  if (signal?.aborted) throw signal.reason ?? new DOMException('Build cancelled.', 'AbortError');
  try {
    const compiled = await compileSvelteComponent(source);
    if (signal?.aborted) throw signal.reason ?? new DOMException('Build cancelled.', 'AbortError');
    const durationMs = Math.round(performance.now() - start);
    return seeds.map((seed) => ({
      ok: true,
      seed,
      durationMs,
      bundle: {
        mode: 'sverlin',
        html: '',
        javascript: compiled.javascript,
        labels: compiled.labels
      }
    }));
  } catch (cause) {
    if (signal?.aborted) throw cause;
    const message = cause instanceof Error ? cause.message : String(cause);
    const durationMs = Math.round(performance.now() - start);
    return seeds.map((seed) => ({
      ok: false,
      seed,
      durationMs,
      error: message,
      diagnostics: [
        {
          severity: 'error',
          message,
          raw: message,
          sourcePath: 'Main.svelte',
          ...(cause instanceof InvalidSvelteSourceError
            ? { code: cause.code, line: cause.line, column: cause.column }
            : {})
        }
      ],
      failureKind: cause instanceof InvalidSvelteSourceError ? 'source' : 'infrastructure'
    }));
  }
}
