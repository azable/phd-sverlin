/** Project-history projections for structured compiler measurements. */

import type { CompilationMetrics, ProjectEvent } from './events';
import type { ProjectDocument } from './model';

/** Return one compiler invocation record in Timeline order without counting a batch per seed. */
export function projectCompilationMetrics(
  value: ProjectDocument | readonly ProjectEvent[]
): CompilationMetrics[] {
  const events = 'events' in value ? value.events : value;
  const seen = new Set<string>();
  const metrics: CompilationMetrics[] = [];

  for (const event of events) {
    if (event.type !== 'compilation.succeeded' && event.type !== 'compilation.failed') continue;
    const current = event.payload.metrics;
    if (!current || seen.has(current.compilationId)) continue;
    seen.add(current.compilationId);
    metrics.push(current);
  }
  return metrics;
}
