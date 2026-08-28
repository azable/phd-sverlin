/** Disposable one-step-ahead compilation cache. Durable project events remain authoritative. */

import type { CompileVisualizationResult } from './compile';
import { compileSource } from './compile';
import { readPreparedCompiler } from './prepared-compiler.js';

type PrefetchRequest = {
  projectId: string;
  sourceContent: string;
  sourceLabel: string;
  sourceSha256: string;
  seed: number;
};

type PrefetchEntry = PrefetchRequest & {
  controller: AbortController;
  promise: Promise<CompileVisualizationResult>;
  result?: Extract<CompileVisualizationResult, { ok: true }>;
};

const entries = new Map<string, PrefetchEntry>();

/** Return an exact prepared result, waiting for matching speculative work if necessary. */
export async function consumePrefetch(
  request: Omit<PrefetchRequest, 'sourceContent'>
): Promise<Extract<CompileVisualizationResult, { ok: true }> | undefined> {
  const entry = entries.get(request.projectId);
  if (!entry || !sameRequest(entry, request)) return undefined;
  const result = entry.result ?? (await entry.promise);
  entries.delete(request.projectId);
  if (!result.ok) return undefined;

  try {
    const prepared = await readPreparedCompiler();
    if (!result.compilerSourceSha256 || result.compilerSourceSha256 !== prepared.sourceSha256) {
      return undefined;
    }
  } catch {
    return undefined;
  }
  return { ...result, debug: { ...result.debug, prefetched: true } };
}

/** Start one low-priority next-seed compile without affecting the current request. */
export function schedulePrefetch(request: PrefetchRequest): void {
  if (!prefetchEnabled()) return;
  const existing = entries.get(request.projectId);
  if (existing && sameRequest(existing, request)) return;
  existing?.controller.abort();

  const controller = new AbortController();
  const promise = compileSource({
    sourceContent: request.sourceContent,
    sourceLabel: request.sourceLabel,
    seed: request.seed,
    owner: `prefetch-${request.projectId}`,
    priority: 'prefetch',
    signal: controller.signal
  });
  const entry: PrefetchEntry = {
    ...request,
    controller,
    promise
  };
  entries.set(request.projectId, entry);
  trimEntries();

  void entry.promise.then((result) => {
    if (entries.get(request.projectId) !== entry) return;
    if (result.ok) entry.result = result;
    else entries.delete(request.projectId);
  });
}

/** Cancel all disposable work during server shutdown. */
export function clearPrefetches(): void {
  for (const entry of entries.values()) entry.controller.abort();
  entries.clear();
}

function sameRequest(
  left: Pick<PrefetchRequest, 'sourceLabel' | 'sourceSha256' | 'seed'>,
  right: Pick<PrefetchRequest, 'sourceLabel' | 'sourceSha256' | 'seed'>
) {
  return (
    left.sourceLabel === right.sourceLabel &&
    left.sourceSha256 === right.sourceSha256 &&
    left.seed === right.seed
  );
}

function prefetchEnabled() {
  if (process.env.NODE_ENV === 'test' && process.env.SVERLIN_PREFETCH_DEPTH === undefined) {
    return false;
  }
  return process.env.SVERLIN_PREFETCH_DEPTH !== '0';
}

function trimEntries() {
  const configured = Number(process.env.SVERLIN_MAX_PREFETCH_PROJECTS ?? '4');
  const maximum = Number.isSafeInteger(configured) && configured > 0 ? configured : 4;
  while (entries.size > maximum) {
    const oldest = entries.entries().next().value as [string, PrefetchEntry] | undefined;
    if (!oldest) return;
    oldest[1].controller.abort();
    entries.delete(oldest[0]);
  }
}
