import * as v from 'valibot';

import type { ProjectDocument, ProjectEvent, ProjectEventType } from './types';

const eventTypes = [
  'project.created',
  'project.renamed',
  'feedback.submitted',
  'ai.generation-requested',
  'ai.generation-succeeded',
  'ai.generation-failed',
  'visualization.render-requested',
  'compilation.requested',
  'compilation.succeeded',
  'compilation.failed',
  'artifact.version-created',
  'visualization.rendered',
  'assistant.responded',
  'system.notified'
] as const satisfies readonly ProjectEventType[];

const nonEmptyString = v.pipe(v.string(), v.nonEmpty());
const safeInteger = v.pipe(v.number(), v.safeInteger());
const nonNegativeInteger = v.pipe(safeInteger, v.minValue(0));
const positiveInteger = v.pipe(safeInteger, v.minValue(1));

const blobRefSchema = v.looseObject({
  sha256: v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/)),
  byteLength: nonNegativeInteger,
  mediaType: nonEmptyString,
  encoding: v.optional(v.literal('utf-8'))
});

const actorSchema = v.variant('kind', [
  v.looseObject({ kind: v.literal('user') }),
  v.looseObject({ kind: v.literal('assistant'), botId: nonEmptyString }),
  v.looseObject({ kind: v.literal('system') })
]);

const diagnosticSchema = v.looseObject({
  severity: v.picklist(['error', 'warning', 'unknown']),
  code: v.optional(v.string()),
  sourcePath: v.optional(v.string()),
  line: v.optional(positiveInteger),
  column: v.optional(positiveInteger),
  message: v.string(),
  raw: v.string()
});

const visualKindSchema = v.variant('kind', [
  v.looseObject({ kind: v.literal('trace') }),
  v.looseObject({ kind: v.literal('group'), children: v.array(safeInteger) })
]);

const colorSchema = v.looseObject({
  hue: v.number(),
  saturation: v.number(),
  lightness: v.number()
});

const visualStyleSchema = v.looseObject({
  top: v.number(),
  left: v.number(),
  width: v.number(),
  height: v.number(),
  opacity: v.optional(v.number()),
  zIndex: v.optional(v.number()),
  padding: v.optional(v.number()),
  fontSize: v.optional(v.number()),
  radius: v.optional(v.number()),
  strokeWidth: v.optional(v.number()),
  alpha: v.optional(v.number()),
  fill: v.optional(colorSchema),
  stroke: v.optional(colorSchema),
  fontFamily: v.optional(v.string()),
  fontWeight: v.optional(v.string()),
  fontStyle: v.optional(v.string()),
  textAlign: v.optional(v.string()),
  borderStyle: v.optional(v.string()),
  whiteSpace: v.optional(v.string())
});

const selectedVisualElementSchema = v.looseObject({
  elementId: safeInteger,
  instanceId: safeInteger,
  role: v.string(),
  content: v.optional(v.string()),
  kind: visualKindSchema,
  style: visualStyleSchema,
  styleVariables: v.array(v.looseObject({ field: v.string(), variables: v.array(v.string()) }))
});

const feedbackAttachmentSchema = v.variant('kind', [
  v.looseObject({
    kind: v.literal('timeline-reference'),
    eventIds: v.pipe(v.array(nonEmptyString), v.minLength(1)),
    relationship: v.picklist(['reference', 'prefer', 'avoid', 'restore-source'])
  }),
  v.looseObject({
    kind: v.literal('visual-selection'),
    renderEventId: nonEmptyString,
    sourceEventId: nonEmptyString,
    judgement: v.picklist(['neutral', 'preferred', 'undesired']),
    step: v.looseObject({ index: nonNegativeInteger, label: v.string() }),
    elements: v.pipe(v.array(selectedVisualElementSchema), v.minLength(1))
  })
]);

const projectArtifactSchema = v.looseObject({
  artifactId: nonEmptyString,
  path: nonEmptyString,
  language: v.literal('sverlin'),
  content: blobRefSchema,
  contentSha256: v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/))
});

const artifactOriginSchema = v.variant('kind', [
  v.looseObject({ kind: v.literal('initial') }),
  v.looseObject({ kind: v.literal('manual-edit') }),
  v.looseObject({ kind: v.literal('assistant-edit'), generationEventId: nonEmptyString }),
  v.looseObject({ kind: v.literal('restore'), restoredFromEventId: nonEmptyString })
]);

const artifactChangeSchema = v.variant('operation', [
  v.looseObject({ operation: v.literal('upsert'), artifact: projectArtifactSchema }),
  v.looseObject({ operation: v.literal('delete'), artifactId: nonEmptyString })
]);

const payloadSchemas = {
  'project.created': v.looseObject({ title: v.string(), entryArtifactId: nonEmptyString }),
  'project.renamed': v.looseObject({ previousTitle: v.string(), title: v.string() }),
  'feedback.submitted': v.looseObject({
    text: v.optional(v.string()),
    attachments: v.array(feedbackAttachmentSchema)
  }),
  'ai.generation-requested': v.looseObject({
    attempt: v.picklist([1, 2]),
    purpose: v.picklist(['initial', 'repair']),
    feedbackEventId: nonEmptyString,
    repairOfCompilationEventId: v.optional(nonEmptyString),
    prompt: blobRefSchema,
    promptSha256: v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/)),
    promptTemplateSha256: v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/)),
    dslApiSha256: v.optional(v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/))),
    requestedModel: nonEmptyString,
    parameters: v.record(v.string(), v.unknown())
  }),
  'ai.generation-succeeded': v.looseObject({
    requestEventId: nonEmptyString,
    attempt: v.picklist([1, 2]),
    adapterId: nonEmptyString,
    botId: nonEmptyString,
    requestedModel: nonEmptyString,
    model: v.optional(nonEmptyString),
    responseId: v.optional(nonEmptyString),
    durationMs: nonNegativeInteger,
    usage: v.optional(v.record(v.string(), v.number())),
    response: blobRefSchema,
    candidateSource: v.optional(blobRefSchema),
    reply: v.string()
  }),
  'ai.generation-failed': v.looseObject({
    requestEventId: nonEmptyString,
    attempt: v.picklist([1, 2]),
    failureKind: v.picklist([
      'configuration',
      'provider',
      'timeout',
      'cancelled',
      'invalid-response'
    ]),
    durationMs: nonNegativeInteger,
    message: v.string(),
    details: v.optional(blobRefSchema)
  }),
  'visualization.render-requested': v.looseObject({
    purpose: v.picklist(['initial', 'seed-change', 'manual-edit', 'assistant-edit', 'restore']),
    seed: positiveInteger,
    source: blobRefSchema,
    sourceSha256: v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/)),
    sourceLabel: nonEmptyString,
    input: v.picklist(['committed-artifact', 'assistant-candidate'])
  }),
  'compilation.requested': v.looseObject({
    renderRequestEventId: nonEmptyString,
    source: blobRefSchema,
    sourceSha256: v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/)),
    sourceLabel: nonEmptyString,
    seed: positiveInteger,
    compilerFingerprint: v.optional(nonEmptyString)
  }),
  'compilation.succeeded': v.looseObject({
    requestEventId: nonEmptyString,
    durationMs: nonNegativeInteger,
    exitCode: safeInteger,
    diagnostics: v.array(diagnosticSchema),
    stdout: blobRefSchema,
    stderr: blobRefSchema,
    render: blobRefSchema,
    renderSha256: v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/)),
    cacheHit: v.boolean()
  }),
  'compilation.failed': v.looseObject({
    requestEventId: nonEmptyString,
    durationMs: nonNegativeInteger,
    exitCode: v.nullable(safeInteger),
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
  }),
  'artifact.version-created': v.looseObject({
    origin: artifactOriginSchema,
    changes: v.pipe(v.array(artifactChangeSchema), v.minLength(1))
  }),
  'visualization.rendered': v.looseObject({
    renderRequestEventId: nonEmptyString,
    compilationEventId: v.optional(nonEmptyString),
    artifactVersionEventId: nonEmptyString,
    artifactVersions: v.record(v.string(), v.string()),
    seed: positiveInteger,
    render: blobRefSchema,
    renderSha256: v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/)),
    sourceSha256: v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/)),
    compilerFingerprint: v.optional(nonEmptyString),
    cacheHit: v.boolean()
  }),
  'assistant.responded': v.looseObject({
    feedbackEventId: nonEmptyString,
    generationEventId: nonEmptyString,
    text: v.string()
  }),
  'system.notified': v.looseObject({
    severity: v.picklist(['info', 'warning', 'error']),
    message: v.string(),
    relatedEventIds: v.array(nonEmptyString)
  })
} as const;

const eventSchema = v.looseObject({
  eventId: nonEmptyString,
  sequence: nonNegativeInteger,
  parentEventId: v.nullable(nonEmptyString),
  type: v.picklist(eventTypes),
  actor: actorSchema,
  correlationId: nonEmptyString,
  causationEventId: v.optional(nonEmptyString),
  createdAt: v.pipe(v.string(), v.isoTimestamp()),
  payload: v.looseObject({})
});

const projectDocumentSchema = v.looseObject({
  schemaVersion: v.literal(1),
  projectId: nonEmptyString,
  events: v.pipe(v.array(eventSchema), v.minLength(1))
});

export class InvalidProjectDocumentError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidProjectDocumentError';
  }
}

export function normalizeProjectV1(value: unknown): ProjectDocument {
  const parsed = v.safeParse(projectDocumentSchema, value);
  if (!parsed.success) throw new InvalidProjectDocumentError(v.summarize(parsed.issues));

  const document = parsed.output as unknown as ProjectDocument;
  validateEventChain(document);
  document.events = document.events.map(normalizeProjectEventV1);
  return document;
}

export function normalizeProjectEventV1(value: unknown): ProjectEvent {
  const parsed = v.safeParse(eventSchema, value);
  if (!parsed.success) throw new InvalidProjectDocumentError(v.summarize(parsed.issues));

  const event = parsed.output as unknown as ProjectEvent;
  const payload = v.safeParse(payloadSchemas[event.type], event.payload);
  if (!payload.success) {
    throw new InvalidProjectDocumentError(
      `Event ${event.eventId} has an invalid payload: ${v.summarize(payload.issues)}`
    );
  }
  event.payload = payload.output as never;
  return event;
}

function validateEventChain(document: ProjectDocument) {
  const ids = new Set<string>();

  document.events.forEach((event, index) => {
    if (event.sequence !== index) {
      throw new InvalidProjectDocumentError(
        `Event ${event.eventId} has a non-contiguous sequence.`
      );
    }

    const expectedParent = index === 0 ? null : document.events[index - 1].eventId;
    if (event.parentEventId !== expectedParent) {
      throw new InvalidProjectDocumentError(
        `Event ${event.eventId} does not extend the project head.`
      );
    }

    if (ids.has(event.eventId)) {
      throw new InvalidProjectDocumentError(`Duplicate event ID ${event.eventId}.`);
    }
    ids.add(event.eventId);

    if (event.causationEventId && !ids.has(event.causationEventId)) {
      throw new InvalidProjectDocumentError(
        `Event ${event.eventId} refers to a causation event outside its history.`
      );
    }
  });

  if (document.events[0]?.type !== 'project.created') {
    throw new InvalidProjectDocumentError('The first event must create the project.');
  }
}
