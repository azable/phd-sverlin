/** Compact source-validation feedback for the bounded assistant repair ladder. */

import type { BuildDiagnostic } from '$lib/shared/projects/events/values';

export function formatDiagnosticSummary(diagnostics: readonly BuildDiagnostic[]): string {
  if (diagnostics.length === 0) return 'The build did not provide a diagnostic.';
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
