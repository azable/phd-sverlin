import { describe, expect, it } from 'vitest';

import type { Visualization } from '$lib/shared/visualization';
import { getProjectTemplate, listProjectTemplates } from '$lib/server/projects/starter-catalog';

import { compileSourceBatch } from './compile';

const runExamples = process.env.SVERLIN_RUN_EXAMPLE_TESTS === '1';
// Production accepts one or two fresh view seeds per compilation. Two fixed
// seeds exercise that complete boundary while keeping the starter suite fast.
const seeds = [1, 2] as const;
const compilerPhases = [
  'sourceInterpretation',
  'renderPlanBuild',
  'semanticTraceBuild',
  'renderExpansion',
  'typographyPreparation',
  'constraintLowering',
  'designSpaceCompilation',
  'designSpaceSampling',
  'irMaterialization',
  'targetEncoding',
  'targetWriting',
  'compilerInternalTotal'
] as const;
const compilerCounts = [
  'semanticDeclarations',
  'semanticVariables',
  'semanticBlocks',
  'semanticRelations',
  'semanticSteps',
  'semanticEvents',
  'planSelections',
  'planRelationSelections',
  'planNodes',
  'planFrames',
  'planConstraints',
  'planContents',
  'planChoices',
  'planConnectors',
  'expandedNodes',
  'expandedConnectors',
  'expandedRankedBlocks',
  'preparedTextRuns',
  'preparedTextBranches',
  'rejectedTextConfigurations',
  'solverInputConstraints',
  'outputViews',
  'outputResources',
  'outputResourceBytes'
] as const;
const viewCounts = [
  'solverVariables',
  'solverNativeBounds',
  'solverRawConstraints',
  'solverCanonicalConstraints',
  'solverEliminatedConstraints',
  'solverChoices',
  'solverChoiceBranches',
  'solverChoiceComponents',
  'solverLargestChoiceComponentBranches',
  'solverAffineEqualities',
  'solverAffineInequalities',
  'samplingAmbientDimension',
  'samplingReducedDimension',
  'samplingEqualities',
  'samplingInequalities',
  'samplingBurnInSteps',
  'outputElements',
  'outputConnectors',
  'outputSteps',
  'outputVariables',
  'outputResources'
] as const;

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
        const results = await compileSourceBatch({
          sourceContent: starter.source,
          sourceLabel: `examples/${starter.file}`,
          seeds,
          owner: 'example-test'
        });
        assertCompleteTimingBreakdown(starter.file, results[0]!.debug);
        for (const [index, result] of results.entries()) {
          const seed = seeds[index]!;
          if (!result.ok) {
            throw new Error(
              `${starter.file} seed ${seed} failed:\n${result.diagnostics.map(({ raw }) => raw).join('\n')}`
            );
          }

          expect(result.visualization.seed).toBe(seed);
          expect(result.visualization.sourcePath).toBe(`examples/${starter.file}`);
          expect(result.visualization.irVersion).toBe(2);
          if (result.visualization.irVersion !== 2) throw new Error('Expected IR version 2.');
          expect(result.visualization.scenarioSeed).toBe(seeds[0]);
          expect(result.visualization.viewSeed).toBe(seed);
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

      const lifecycle = compiled.get('lifecycle:1')!;
      expect(lifecycle.steps).toHaveLength(2);
      expect(lifecycle.steps.every(({ occurrenceKey }) => occurrenceKey !== undefined)).toBe(true);
      const addition = compiled.get('typed-addition:2')!;
      expect(JSON.stringify(addition)).toContain('"layoutSource":"42"');
      expect(addition.elements.some(({ children }) => children.length >= 1)).toBe(true);

      const linearSearchOutputs = seeds.map((seed) => compiled.get(`linear-search:${seed}`)!);
      expect(linearSearchOutputs.every(({ steps }) => steps.length >= 4)).toBe(true);
      expect(
        linearSearchOutputs.some(({ steps }) =>
          steps.some(({ instances }) =>
            instances.some(({ fragmentClusters }) => (fragmentClusters?.length ?? 0) > 0)
          )
        )
      ).toBe(true);

      const continuity = compiled.get('continuity-and-fork:2')!;
      expect(
        continuity.steps.some(({ instances }) =>
          instances.some(({ originElementId }) => originElementId !== undefined)
        )
      ).toBe(true);

      const cspOutputs = seeds.map((seed) => compiled.get(`csp-compositions:${seed}`)!);
      const alternatives = new Set(cspOutputs.map(compositionAlternative));
      const orientations = new Set(cspOutputs.map(compositionOrientation));
      expect(alternatives).toEqual(new Set(['row', 'column']));
      expect(orientations).toEqual(new Set(['row', 'column']));
    }
  );
});

function assertCompleteTimingBreakdown(
  source: string,
  debug: {
    durationMs: number;
    compilerMetrics?: {
      phasesMs: Record<string, number>;
      counts: Record<string, number>;
      views: Array<{ counts: Record<string, number> }>;
    };
    serviceMetrics?: {
      totalMs: number;
      requestPreparationMs: number;
      queueWaitMs: number;
      compilerProcessMs: number;
      outputValidationMs: number;
      cleanupMs: number;
    };
  }
) {
  const compiler = debug.compilerMetrics;
  const service = debug.serviceMetrics;
  expect(compiler, `${source} compiler metrics`).toBeDefined();
  expect(service, `${source} service metrics`).toBeDefined();
  if (!compiler || !service) return;

  expect(Object.keys(compiler.phasesMs)).toEqual(expect.arrayContaining([...compilerPhases]));
  expect(Object.keys(compiler.counts)).toEqual(expect.arrayContaining([...compilerCounts]));
  expect(compiler.views).toHaveLength(seeds.length);
  for (const view of compiler.views) {
    expect(Object.keys(view.counts)).toEqual(expect.arrayContaining([...viewCounts]));
  }

  const internalTotal = compiler.phasesMs.compilerInternalTotal!;
  for (const phase of compilerPhases) {
    expect(compiler.phasesMs[phase], `${source} ${phase}`).toBeLessThanOrEqual(internalTotal + 0.1);
  }
  expect(internalTotal).toBeLessThanOrEqual(service.compilerProcessMs + 0.1);
  for (const duration of [
    service.requestPreparationMs,
    service.queueWaitMs,
    service.compilerProcessMs,
    service.outputValidationMs,
    service.cleanupMs
  ]) {
    expect(duration).toBeLessThanOrEqual(service.totalMs + 0.1);
  }
}

function compositionAlternative(visualization: Visualization): string | undefined {
  const variable = visualization.variables.find(
    ({ value }) => value.kind === 'category' && ['row', 'column'].includes(value.value)
  );
  return variable?.value.kind === 'category' ? variable.value.value : undefined;
}

function compositionOrientation(visualization: Visualization): 'row' | 'column' {
  const [first, second] = visualization.elements.filter(({ id }) => id >= 0);
  const horizontal = Math.abs(second.box.bounds.rectX - first.box.bounds.rectX);
  const vertical = Math.abs(second.box.bounds.rectY - first.box.bounds.rectY);
  return horizontal > vertical ? 'row' : 'column';
}
