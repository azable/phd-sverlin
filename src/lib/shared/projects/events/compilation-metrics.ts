/** Versioned structured timings and workload sizes for one compiler invocation. */

import * as v from 'valibot';

import { naturalSchema, operationIdSchema, positiveSchema } from './values';

const millisecondsSchema = v.pipe(v.number(), v.finite(), v.minValue(0));

const compilerPhaseSchema = v.picklist([
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
]);

const compilerCountSchema = v.picklist([
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
]);

const viewCountSchema = v.picklist([
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
]);

export const compilerViewMetricsSchema = v.strictObject({
  seed: positiveSchema,
  materializationMs: millisecondsSchema,
  counts: v.record(viewCountSchema, naturalSchema),
  labels: v.strictObject({
    solverBackend: v.literal('affine-sampler'),
    decisionCoverage: v.picklist(['exact-enumeration', 'mip-conditioning', 'legacy'])
  })
});

/** Private compiler-process sidecar parsed by the visualization service. */
export const compilerMetricsSidecarSchema = v.strictObject({
  schemaVersion: v.literal(1),
  viewSeeds: v.array(positiveSchema),
  phasesMs: v.record(compilerPhaseSchema, millisecondsSchema),
  counts: v.record(compilerCountSchema, naturalSchema),
  views: v.array(compilerViewMetricsSchema),
  failedPhase: v.nullable(compilerPhaseSchema)
});

const serviceMetricsSchema = v.strictObject({
  totalMs: millisecondsSchema,
  requestPreparationMs: millisecondsSchema,
  queueWaitMs: millisecondsSchema,
  compilerProcessMs: millisecondsSchema,
  outputValidationMs: millisecondsSchema,
  cleanupMs: millisecondsSchema
});

/** Complete compiler-service record persisted in project compilation events. */
export const compilationMetricsSchema = v.strictObject({
  schemaVersion: v.literal(1),
  compilationId: operationIdSchema,
  viewSeeds: v.array(positiveSchema),
  requestedViewCount: positiveSchema,
  producedViewCount: naturalSchema,
  service: serviceMetricsSchema,
  compiler: v.optional(compilerMetricsSidecarSchema)
});

export type CompilerMetricsSidecar = v.InferOutput<typeof compilerMetricsSidecarSchema>;
export type CompilationMetrics = v.InferOutput<typeof compilationMetricsSchema>;
