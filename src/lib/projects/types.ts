import * as v from 'valibot';

import type { CompiledVisualization, RenderInstanceId } from '$lib/visualization/types';

const text = v.pipe(v.string(), v.nonEmpty());
const integer = v.pipe(v.number(), v.safeInteger());
const natural = v.pipe(integer, v.minValue(0));
const positive = v.pipe(integer, v.minValue(1));
const sha256 = v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/));
const gitCommit = v.pipe(v.string(), v.regex(/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/));
const operationId = v.pipe(v.string(), v.uuid());

export const blobRefSchema = v.object({
  sha256,
  byteLength: natural,
  mediaType: text
});

const actorSchema = v.variant('kind', [
  v.object({ kind: v.literal('user') }),
  v.object({ kind: v.literal('assistant'), botId: text }),
  v.object({ kind: v.literal('system') })
]);

const diagnosticSchema = v.object({
  severity: v.picklist(['error', 'warning', 'unknown']),
  code: v.optional(v.string()),
  sourcePath: v.optional(v.string()),
  line: v.optional(positive),
  column: v.optional(positive),
  message: v.string(),
  raw: v.string()
});

const projectArtifactSchema = v.object({
  artifactId: text,
  path: text,
  language: v.literal('sverlin'),
  content: blobRefSchema
});

const artifactOriginSchema = v.variant('kind', [
  v.object({ kind: v.literal('initial') }),
  v.object({ kind: v.literal('manual-edit') }),
  v.object({ kind: v.literal('assistant-edit') }),
  v.object({ kind: v.literal('restore'), restoredFrom: positive })
]);

const artifactChangeSchema = v.variant('operation', [
  v.object({ operation: v.literal('upsert'), artifact: projectArtifactSchema }),
  v.object({ operation: v.literal('delete'), artifactId: text })
]);

export const visualSelectionSchema = v.object({
  render: positive,
  step: natural,
  instances: v.pipe(v.array(positive), v.minLength(1)),
  judgement: v.picklist(['neutral', 'preferred', 'undesired'])
});

export const dslRevisionSchema = v.object({
  contentSha256: sha256,
  repositoryCommit: v.optional(gitCommit),
  workingTree: v.picklist(['clean', 'dirty', 'unknown'])
});

const envelope = {
  id: positive,
  operationId,
  actor: actorSchema,
  createdAt: v.pipe(v.string(), v.isoTimestamp())
};

const projectCreatedEventSchema = v.object({
  ...envelope,
  type: v.literal('project.created'),
  payload: v.object({ title: v.string(), entryArtifactId: text })
});

const projectRenamedEventSchema = v.object({
  ...envelope,
  type: v.literal('project.renamed'),
  payload: v.object({ previousTitle: v.string(), title: v.string() })
});

const feedbackSubmittedEventSchema = v.object({
  ...envelope,
  type: v.literal('feedback.submitted'),
  payload: v.object({
    text: v.optional(v.string()),
    focus: v.array(positive),
    selection: v.optional(visualSelectionSchema)
  })
});

const aiGenerationRequestedEventSchema = v.object({
  ...envelope,
  type: v.literal('ai.generation-requested'),
  payload: v.object({
    attempt: v.picklist([1, 2]),
    purpose: v.picklist(['initial', 'repair']),
    prompt: blobRefSchema,
    promptTemplateSha256: sha256,
    dslRevision: v.optional(dslRevisionSchema),
    requestedModel: text,
    parameters: v.record(v.string(), v.unknown())
  })
});

const aiGenerationSucceededEventSchema = v.object({
  ...envelope,
  type: v.literal('ai.generation-succeeded'),
  payload: v.object({
    attempt: v.picklist([1, 2]),
    adapterId: text,
    requestedModel: text,
    model: v.optional(text),
    responseId: v.optional(text),
    durationMs: natural,
    usage: v.optional(v.record(v.string(), v.number())),
    response: blobRefSchema
  })
});

const aiGenerationFailedEventSchema = v.object({
  ...envelope,
  type: v.literal('ai.generation-failed'),
  payload: v.object({
    attempt: v.picklist([1, 2]),
    failureKind: v.picklist([
      'configuration',
      'provider',
      'timeout',
      'cancelled',
      'invalid-response'
    ]),
    durationMs: natural,
    message: v.string(),
    details: v.optional(blobRefSchema)
  })
});

export const renderPurposeSchema = v.picklist([
  'initial',
  'seed-change',
  'manual-edit',
  'assistant-edit',
  'restore'
]);

const compilationRequestedEventSchema = v.object({
  ...envelope,
  type: v.literal('compilation.requested'),
  payload: v.object({
    purpose: renderPurposeSchema,
    input: v.picklist(['committed-artifact', 'assistant-candidate']),
    source: blobRefSchema,
    sourceLabel: text,
    seed: positive,
    attempt: v.optional(v.picklist([1, 2])),
    dslRevision: v.optional(dslRevisionSchema)
  })
});

const compilationSucceededEventSchema = v.object({
  ...envelope,
  type: v.literal('compilation.succeeded'),
  payload: v.object({
    durationMs: natural,
    stdout: blobRefSchema,
    stderr: blobRefSchema,
    render: blobRefSchema
  })
});

const compilationFailedEventSchema = v.object({
  ...envelope,
  type: v.literal('compilation.failed'),
  payload: v.object({
    durationMs: natural,
    exitCode: v.nullable(integer),
    failureKind: v.picklist([
      'source',
      'pipeline',
      'infrastructure',
      'timeout',
      'invalid-output',
      'cancelled'
    ]),
    diagnostics: v.array(diagnosticSchema),
    stdout: blobRefSchema,
    stderr: blobRefSchema,
    timedOut: v.boolean(),
    repairEligible: v.boolean(),
    error: v.optional(v.string())
  })
});

const artifactVersionCreatedEventSchema = v.object({
  ...envelope,
  type: v.literal('artifact.version-created'),
  payload: v.object({
    origin: artifactOriginSchema,
    changes: v.pipe(v.array(artifactChangeSchema), v.minLength(1))
  })
});

const visualizationRenderedEventSchema = v.object({
  ...envelope,
  type: v.literal('visualization.rendered'),
  payload: v.object({ seed: positive, source: blobRefSchema, render: blobRefSchema })
});

const assistantRespondedEventSchema = v.object({
  ...envelope,
  type: v.literal('assistant.responded'),
  payload: v.object({ text: v.string() })
});

const systemNotifiedEventSchema = v.object({
  ...envelope,
  type: v.literal('system.notified'),
  payload: v.object({
    severity: v.picklist(['info', 'warning', 'error']),
    message: v.string()
  })
});

export const projectEventSchema = v.variant('type', [
  projectCreatedEventSchema,
  projectRenamedEventSchema,
  feedbackSubmittedEventSchema,
  aiGenerationRequestedEventSchema,
  aiGenerationSucceededEventSchema,
  aiGenerationFailedEventSchema,
  compilationRequestedEventSchema,
  compilationSucceededEventSchema,
  compilationFailedEventSchema,
  artifactVersionCreatedEventSchema,
  visualizationRenderedEventSchema,
  assistantRespondedEventSchema,
  systemNotifiedEventSchema
]);

export const projectDocumentSchema = v.object({
  schemaVersion: v.literal(1),
  projectId: text,
  events: v.pipe(v.array(projectEventSchema), v.minLength(1))
});

const commandBase = { operationId, expectedHead: positive };

export const projectCommandSchema = v.variant('type', [
  v.object({ ...commandBase, type: v.literal('rename'), title: text }),
  v.object({
    ...commandBase,
    type: v.literal('feedback'),
    text: v.optional(v.string()),
    focus: v.array(positive),
    selection: v.optional(visualSelectionSchema),
    seed: positive
  }),
  v.object({ ...commandBase, type: v.literal('render'), seed: positive }),
  v.object({
    ...commandBase,
    type: v.literal('save'),
    artifactId: text,
    source: v.string(),
    seed: positive
  }),
  v.object({
    ...commandBase,
    type: v.literal('restore'),
    from: positive,
    seed: positive
  })
]);

export type BlobRef = v.InferOutput<typeof blobRefSchema>;
export type ProjectActor = v.InferOutput<typeof actorSchema>;
export type ProjectArtifact = v.InferOutput<typeof projectArtifactSchema>;
export type ArtifactChange = v.InferOutput<typeof artifactChangeSchema>;
export type ArtifactVersionOrigin = v.InferOutput<typeof artifactOriginSchema>;
export type VisualSelection = Omit<v.InferOutput<typeof visualSelectionSchema>, 'instances'> & {
  instances: RenderInstanceId[];
};
export type DslRevision = v.InferOutput<typeof dslRevisionSchema>;
export type ProjectEvent = v.InferOutput<typeof projectEventSchema>;
export type ProjectEventType = ProjectEvent['type'];
export type ProjectDocument = v.InferOutput<typeof projectDocumentSchema>;
export type ProjectCommand = v.InferOutput<typeof projectCommandSchema>;
export type ProjectCommandInput = ProjectCommand extends infer Command
  ? Command extends ProjectCommand
    ? Omit<Command, 'operationId' | 'expectedHead'>
    : never
  : never;
export type EventId = ProjectEvent['id'];
export type ProjectId = string;
export type ArtifactId = string;
export type ProjectConnectionState = 'connecting' | 'open' | 'reconnecting';
export type RenderPurpose = v.InferOutput<typeof renderPurposeSchema>;
export type FeedbackSubmittedEvent = Extract<ProjectEvent, { type: 'feedback.submitted' }>;

export type NewProjectEvent<Type extends ProjectEventType = ProjectEventType> = Omit<
  Extract<ProjectEvent, { type: Type }>,
  'id'
>;

export type ProjectSnapshot = {
  at: EventId;
  title: string;
  entryArtifactId: ArtifactId;
  artifacts: Record<ArtifactId, ProjectArtifact>;
  activeRender?: Extract<ProjectEvent, { type: 'visualization.rendered' }>;
};

export type HydratedProjectArtifact = ProjectArtifact & { source: string };

export type ProjectView = {
  document: ProjectDocument;
  snapshot: Omit<ProjectSnapshot, 'artifacts'> & {
    artifacts: Record<ArtifactId, HydratedProjectArtifact>;
  };
  trace?: CompiledVisualization;
  projects: ProjectSummary[];
};

export type ProjectSummary = {
  projectId: ProjectId;
  title: string;
  updatedAt: string;
  eventCount: number;
};

export type ProjectCommandResult = {
  document: ProjectDocument;
  appendedEvents: ProjectEvent[];
};

export class InvalidProjectDocumentError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidProjectDocumentError';
  }
}

export function normalizeProjectV1(value: unknown): ProjectDocument {
  const parsed = v.safeParse(projectDocumentSchema, value);
  if (!parsed.success) throw new InvalidProjectDocumentError(v.summarize(parsed.issues));
  validateEventIds(parsed.output);
  return parsed.output;
}

export function normalizeProjectEventV1(value: unknown): ProjectEvent {
  const parsed = v.safeParse(projectEventSchema, value);
  if (!parsed.success) throw new InvalidProjectDocumentError(v.summarize(parsed.issues));
  return parsed.output;
}

export function parseProjectCommand(value: unknown): ProjectCommand {
  const parsed = v.safeParse(projectCommandSchema, value);
  if (!parsed.success) throw new InvalidProjectDocumentError(v.summarize(parsed.issues));
  return parsed.output;
}

function validateEventIds(document: ProjectDocument) {
  document.events.forEach((event, index) => {
    if (event.id !== index + 1) {
      throw new InvalidProjectDocumentError(
        `Event ${event.id} is not at its stable 1-based position ${index + 1}.`
      );
    }
  });
  if (document.events[0].type !== 'project.created') {
    throw new InvalidProjectDocumentError('The first event must create the project.');
  }
}
