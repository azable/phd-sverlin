import { describe, expect, it } from 'vitest';

import type { Visualization } from '$lib/shared/visualization';
import { getProjectTemplate, listProjectTemplates } from '$lib/server/projects/starter-catalog';

import { compileSource } from './compile';

const runExamples = process.env.SVERLIN_RUN_EXAMPLE_TESTS === '1';
const seeds = [1, 2, 7, 11] as const;

describe.skipIf(!runExamples)('catalogued Sverlin examples', () => {
  it(
    'compiles every starter through the production boundary and preserves its contract',
    { timeout: 900_000 },
    async () => {
      const starters = listProjectTemplates().map((summary) => ({
        ...getProjectTemplate(summary.id),
        meaningful: summary.id !== 'blank'
      }));
      const compiled = new Map<string, Visualization>();

      for (const starter of starters) {
        for (const seed of seeds) {
          const result = await compileSource({
            sourceContent: starter.source,
            sourceLabel: `examples/${starter.file}`,
            seed,
            owner: 'example-test'
          });
          if (!result.ok) {
            throw new Error(
              `${starter.file} seed ${seed} failed:\n${result.diagnostics.map(({ raw }) => raw).join('\n')}`
            );
          }

          expect(result.visualization.seed).toBe(seed);
          expect(result.visualization.sourcePath).toBe(`examples/${starter.file}`);
          expect(result.targetDiagnostics.filter(({ severity }) => severity === 'warning')).toEqual(
            []
          );
          expect(result.visualization.elements.length).toBeGreaterThanOrEqual(
            starter.meaningful ? 2 : 1
          );
          if (starter.meaningful) expect(result.visualization.steps.length).toBeGreaterThan(1);
          compiled.set(`${starter.id}:${seed}`, result.visualization);
        }
      }

      expect(stepLabels(compiled.get('lifecycle:1')!)).toEqual([
        'Value is live',
        'Value is destroyed'
      ]);
      const addition = compiled.get('typed-addition:2')!;
      expect(JSON.stringify(addition)).toContain('"layoutSource":"42"');
      expect(addition.elements.some(({ children }) => children.length === 4)).toBe(true);
      expect(stepLabels(compiled.get('linear-search:7')!)).toContain('Found target');
      expect(JSON.stringify(compiled.get('linear-search:7'))).toContain('codeTextContent');

      const continuity = compiled.get('continuity-and-fork:7')!;
      const original = continuity.steps.find(({ label }) => label === 'Original')!.instances[0];
      const forked = continuity.steps.find(({ label }) => label === 'Forked')!.instances;
      const selected = continuity.steps.find(({ label }) => label === 'Selected')!.instances;
      const cleared = continuity.steps.find(
        ({ label }) => label === 'Selection cleared'
      )!.instances;
      expect(forked.find(({ id }) => id !== original.id)?.originElementId).toBe(original.elementId);
      expect(selected.some(({ id }) => id === original.id)).toBe(true);
      expect(cleared.some(({ id }) => id === original.id)).toBe(true);

      const cspOutputs = seeds.map((seed) => compiled.get(`csp-compositions:${seed}`)!);
      const alternatives = new Set(cspOutputs.map(compositionAlternative));
      const orientations = new Set(cspOutputs.map(compositionOrientation));
      expect(alternatives).toEqual(new Set(['row', 'column']));
      expect(orientations).toEqual(new Set(['row', 'column']));
    }
  );
});

function stepLabels(visualization: Visualization): string[] {
  return visualization.steps.map(({ label }) => label);
}

function compositionAlternative(visualization: Visualization): string | undefined {
  const variable = visualization.variables.find(({ id }) => id === 'pipeline.composition');
  return variable?.value.kind === 'category' ? variable.value.value : undefined;
}

function compositionOrientation(visualization: Visualization): 'row' | 'column' {
  const [first, second] = visualization.elements.filter(({ id }) => id >= 0);
  const horizontal = Math.abs(second.box.bounds.rectX - first.box.bounds.rectX);
  const vertical = Math.abs(second.box.bounds.rectY - first.box.bounds.rectY);
  return horizontal > vertical ? 'row' : 'column';
}
