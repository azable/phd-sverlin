/** Discover server-only mode builders by folder convention from the public catalogue. */

import { modeCatalog } from './catalog';
import type { VisualizationMode, RenderablePresentation } from '$lib/shared/presentations';
import type { BuildDiagnostic } from '$lib/shared/projects/events/values';

export type ModeBuilder = (
  source: string,
  seed: number,
  generationEventId?: number
) => Promise<RenderablePresentation>;

export type ModeBuildResult =
  | {
      ok: true;
      seed: number;
      durationMs: number;
      bundle: { mode: VisualizationMode; html: string; javascript: string; labels: string[] };
    }
  | {
      ok: false;
      seed: number;
      durationMs: number;
      error: string;
      diagnostics: BuildDiagnostic[];
      failureKind: 'source' | 'infrastructure';
    };

export type ModeBatchBuilder = (
  source: string,
  seeds: readonly number[],
  signal?: AbortSignal
) => Promise<ModeBuildResult[]>;

const modules = import.meta.glob<{
  buildPresentation?: ModeBuilder;
  buildBatch?: ModeBatchBuilder;
}>('./*/build.server.ts', {
  eager: true
});

export const directModeBuilders = Object.fromEntries(
  Object.keys(modeCatalog).map((id) => [id, modules[`./${id}/build.server.ts`]?.buildPresentation])
) as Record<VisualizationMode, ModeBuilder | undefined>;

export const sourceModeBuilders = Object.fromEntries(
  Object.keys(modeCatalog).map((id) => [id, modules[`./${id}/build.server.ts`]?.buildBatch])
) as Record<VisualizationMode, ModeBatchBuilder | undefined>;

for (const pathname of Object.keys(modules)) {
  const id = pathname.split('/').at(-2) ?? '';
  if (!(id in modeCatalog)) throw new Error(`Unregistered visualization mode folder ${id}.`);
}

for (const [id, registration] of Object.entries(modeCatalog)) {
  const module = modules[`./${id}/build.server.ts`];
  const supported =
    registration.authoring === 'source' ? module?.buildBatch : module?.buildPresentation;
  if (!supported) throw new Error(`Visualization mode ${id} needs a matching server builder.`);
}
