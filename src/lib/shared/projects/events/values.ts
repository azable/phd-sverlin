/**
 * Shared validation fragments and values used by project events.
 *
 * @packageDocumentation
 */

import * as v from 'valibot';

import type { RenderInstanceId } from '$lib/shared/visualization';

/** Runtime schema for non-empty text stored in project events. */
export const textSchema = v.pipe(v.string(), v.nonEmpty());
/** Runtime schema for safe integer values. */
export const integerSchema = v.pipe(v.number(), v.safeInteger());
/** Runtime schema for non-negative safe integer values. */
export const naturalSchema = v.pipe(integerSchema, v.minValue(0));
/** Runtime schema for positive safe integer values. */
export const positiveSchema = v.pipe(integerSchema, v.minValue(1));
/** Runtime schema for lowercase SHA-256 digests. */
export const sha256Schema = v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/));
/** Runtime schema for content-addressed resource identifiers. */
export const resourceIdSchema = v.pipe(v.string(), v.regex(/^sha256-[a-f0-9]{64}$/));
/** Runtime schema for project operation UUIDs. */
export const operationIdSchema = v.pipe(v.string(), v.uuid());

const gitCommitSchema = v.pipe(v.string(), v.regex(/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/));

/** Runtime schema for immutable text embedded directly in project history. */
export const recordedTextSchema = v.object({
  text: v.string(),
  sha256: sha256Schema,
  mediaType: textSchema
});

/** Runtime schema for the actor responsible for a project event. */
export const actorSchema = v.variant('kind', [
  v.object({ kind: v.literal('user') }),
  v.object({ kind: v.literal('assistant'), botId: textSchema }),
  v.object({ kind: v.literal('system') })
]);

/** Runtime schema for compiler diagnostics recorded in project history. */
export const diagnosticSchema = v.object({
  severity: v.picklist(['error', 'warning', 'unknown']),
  code: v.optional(v.string()),
  sourcePath: v.optional(v.string()),
  line: v.optional(positiveSchema),
  column: v.optional(positiveSchema),
  message: v.string(),
  raw: v.string()
});

/** Runtime schema for an immutable compiler resource stored outside the event log. */
export const compilationResourceSchema = v.object({
  id: resourceIdSchema,
  kind: v.picklist(['fontResource', 'textRunResource', 'vectorResource']),
  sha256: sha256Schema,
  mediaType: textSchema,
  byteLength: naturalSchema
});

/** Runtime schema for the deterministic compiler package/toolchain contract. */
export const compilationProvenanceSchema = v.object({
  packageVersion: positiveSchema,
  textRunFormatVersion: positiveSchema,
  shapingEngine: textSchema,
  shapingEngineVersion: textSchema,
  fontCatalogSha256: v.optional(sha256Schema)
});

/** Runtime schema for a successful output target's non-fatal diagnostic. */
export const targetDiagnosticSchema = v.object({
  severity: v.picklist(['info', 'warning']),
  code: textSchema,
  message: v.string()
});

/** Runtime schema for source artifacts tracked by a project. */
export const projectArtifactSchema = v.object({
  artifactId: textSchema,
  path: textSchema,
  language: v.picklist(['sverlin', 'json']),
  content: recordedTextSchema
});

/** Runtime schema for artifact-version provenance. */
export const artifactOriginSchema = v.variant('kind', [
  v.object({ kind: v.literal('initial') }),
  v.object({ kind: v.literal('manual-edit') }),
  v.object({ kind: v.literal('assistant-edit') }),
  v.object({ kind: v.literal('restore'), restoredFrom: positiveSchema })
]);

/** Runtime schema for an artifact upsert or deletion. */
export const artifactChangeSchema = v.variant('operation', [
  v.object({ operation: v.literal('upsert'), artifact: projectArtifactSchema }),
  v.object({ operation: v.literal('delete'), artifactId: textSchema })
]);

/** Runtime schema for feedback attached to concrete visualization instances. */
export const visualSelectionSchema = v.object({
  render: positiveSchema,
  step: naturalSchema,
  instances: v.pipe(v.array(naturalSchema), v.minLength(1))
});

/** Runtime schema identifying the exact DSL implementation used for a compilation. */
export const dslRevisionSchema = v.object({
  contentSha256: sha256Schema,
  repositoryCommit: v.optional(gitCommitSchema),
  workingTree: v.picklist(['clean', 'dirty', 'unknown'])
});

/** Runtime schema for the reason a visualization render was requested. */
export const renderPurposeSchema = v.picklist([
  'initial',
  'seed-change',
  'manual-edit',
  'assistant-edit',
  'restore'
]);

/** Validation fields shared by every immutable project event. */
export const eventEnvelope = {
  id: positiveSchema,
  operationId: operationIdSchema,
  actor: actorSchema,
  createdAt: v.pipe(v.string(), v.isoTimestamp())
};

/** Immutable text and its provenance embedded directly in a project event. */
export type RecordedText = v.InferOutput<typeof recordedTextSchema>;
/** Structured compiler diagnostic retained in project history. */
export type CompilerDiagnostic = v.InferOutput<typeof diagnosticSchema>;
/** Content-addressed compiler resource referenced by project events. */
export type CompilationResource = v.InferOutput<typeof compilationResourceSchema>;
/** Versioned compiler package and shaping-engine provenance. */
export type CompilationProvenance = v.InferOutput<typeof compilationProvenanceSchema>;
/** Non-fatal diagnostic emitted by a concrete output target. */
export type TargetDiagnostic = v.InferOutput<typeof targetDiagnosticSchema>;
/** Metadata for one versioned project source artifact. */
export type ProjectArtifact = v.InferOutput<typeof projectArtifactSchema>;
/** Upsert or deletion applied by an artifact-version event. */
export type ArtifactChange = v.InferOutput<typeof artifactChangeSchema>;
/** Provenance of an artifact version. */
export type ArtifactVersionOrigin = v.InferOutput<typeof artifactOriginSchema>;
/** Feedback selection tied to render instances at a specific visualization step. */
export type VisualSelection = Omit<v.InferOutput<typeof visualSelectionSchema>, 'instances'> & {
  instances: RenderInstanceId[];
};
/** Fingerprint of the DSL implementation used to compile a visualization. */
export type DslRevision = v.InferOutput<typeof dslRevisionSchema>;
/** Reason a visualization render was requested. */
export type RenderPurpose = v.InferOutput<typeof renderPurposeSchema>;
