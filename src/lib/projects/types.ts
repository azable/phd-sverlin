import type {
  CompilerDiagnostic,
  CompileFailureKind,
  CompiledVisualization
} from '$lib/visualization/types';
import type {
  StyleVariableBinding,
  VisualElementKind,
  VisualStyle
} from '$lib/visualization/generated/visualization-ir';

export type ProjectId = string;
export type ProjectEventId = string;
export type ProjectCorrelationId = string;
export type ArtifactId = string;

export type BlobRef = {
  sha256: string;
  byteLength: number;
  mediaType: string;
  encoding?: 'utf-8';
};

export type ProjectActor =
  | { kind: 'user' }
  | { kind: 'assistant'; botId: string }
  | { kind: 'system' };

export type ProjectEventEnvelope<Type extends string, Payload> = {
  eventId: ProjectEventId;
  sequence: number;
  parentEventId: ProjectEventId | null;
  type: Type;
  actor: ProjectActor;
  correlationId: ProjectCorrelationId;
  causationEventId?: ProjectEventId;
  createdAt: string;
  payload: Payload;
};

export type ProjectCreatedEvent = ProjectEventEnvelope<
  'project.created',
  { title: string; entryArtifactId: ArtifactId }
>;

export type ProjectRenamedEvent = ProjectEventEnvelope<
  'project.renamed',
  { previousTitle: string; title: string }
>;

export type TimelineReferenceAttachment = {
  kind: 'timeline-reference';
  eventIds: ProjectEventId[];
  relationship: 'reference' | 'prefer' | 'avoid' | 'restore-source';
};

export type SelectedVisualElement = {
  elementId: number;
  instanceId: number;
  role: string;
  content?: string;
  kind: VisualElementKind;
  style: VisualStyle;
  styleVariables: StyleVariableBinding[];
};

export type VisualSelectionAttachment = {
  kind: 'visual-selection';
  renderEventId: ProjectEventId;
  sourceEventId: ProjectEventId;
  judgement: 'neutral' | 'preferred' | 'undesired';
  step: { index: number; label: string };
  elements: SelectedVisualElement[];
};

export type FeedbackAttachment = TimelineReferenceAttachment | VisualSelectionAttachment;

export type FeedbackSubmittedEvent = ProjectEventEnvelope<
  'feedback.submitted',
  { text?: string; attachments: FeedbackAttachment[] }
>;

export type AiGenerationRequestedEvent = ProjectEventEnvelope<
  'ai.generation-requested',
  {
    attempt: 1 | 2;
    purpose: 'initial' | 'repair';
    feedbackEventId: ProjectEventId;
    repairOfCompilationEventId?: ProjectEventId;
    prompt: BlobRef;
    promptSha256: string;
    promptTemplateSha256: string;
    dslApiSha256?: string;
    requestedModel: string;
    parameters: Record<string, unknown>;
  }
>;

export type AiGenerationSucceededEvent = ProjectEventEnvelope<
  'ai.generation-succeeded',
  {
    requestEventId: ProjectEventId;
    attempt: 1 | 2;
    adapterId: string;
    botId: string;
    requestedModel: string;
    model?: string;
    responseId?: string;
    durationMs: number;
    usage?: Record<string, number>;
    response: BlobRef;
    candidateSource?: BlobRef;
    reply: string;
  }
>;

export type AiGenerationFailedEvent = ProjectEventEnvelope<
  'ai.generation-failed',
  {
    requestEventId: ProjectEventId;
    attempt: 1 | 2;
    failureKind: 'configuration' | 'provider' | 'timeout' | 'cancelled' | 'invalid-response';
    durationMs: number;
    message: string;
    details?: BlobRef;
  }
>;

export type RenderPurpose =
  | 'initial'
  | 'seed-change'
  | 'manual-edit'
  | 'assistant-edit'
  | 'restore';

export type VisualizationRenderRequestedEvent = ProjectEventEnvelope<
  'visualization.render-requested',
  {
    purpose: RenderPurpose;
    seed: number;
    source: BlobRef;
    sourceSha256: string;
    sourceLabel: string;
    input: 'committed-artifact' | 'assistant-candidate';
  }
>;

export type CompilationRequestedEvent = ProjectEventEnvelope<
  'compilation.requested',
  {
    renderRequestEventId: ProjectEventId;
    source: BlobRef;
    sourceSha256: string;
    sourceLabel: string;
    seed: number;
    compilerFingerprint?: string;
  }
>;

export type CompilationSucceededEvent = ProjectEventEnvelope<
  'compilation.succeeded',
  {
    requestEventId: ProjectEventId;
    durationMs: number;
    exitCode: number;
    diagnostics: CompilerDiagnostic[];
    stdout: BlobRef;
    stderr: BlobRef;
    render: BlobRef;
    renderSha256: string;
    cacheHit: boolean;
  }
>;

export type CompilationFailedEvent = ProjectEventEnvelope<
  'compilation.failed',
  {
    requestEventId: ProjectEventId;
    durationMs: number;
    exitCode: number | null;
    failureKind: CompileFailureKind;
    diagnostics: CompilerDiagnostic[];
    stdout: BlobRef;
    stderr: BlobRef;
    timedOut: boolean;
    repairEligible: boolean;
    error?: string;
  }
>;

export type ArtifactVersionOrigin =
  | { kind: 'initial' }
  | { kind: 'manual-edit' }
  | { kind: 'assistant-edit'; generationEventId: ProjectEventId }
  | { kind: 'restore'; restoredFromEventId: ProjectEventId };

export type ProjectArtifact = {
  artifactId: ArtifactId;
  path: string;
  language: 'sverlin';
  content: BlobRef;
  contentSha256: string;
};

export type ArtifactChange =
  | { operation: 'upsert'; artifact: ProjectArtifact }
  | { operation: 'delete'; artifactId: ArtifactId };

export type ArtifactVersionCreatedEvent = ProjectEventEnvelope<
  'artifact.version-created',
  { origin: ArtifactVersionOrigin; changes: ArtifactChange[] }
>;

export type VisualizationRenderedEvent = ProjectEventEnvelope<
  'visualization.rendered',
  {
    renderRequestEventId: ProjectEventId;
    compilationEventId?: ProjectEventId;
    artifactVersionEventId: ProjectEventId;
    artifactVersions: Record<ArtifactId, string>;
    seed: number;
    render: BlobRef;
    renderSha256: string;
    sourceSha256: string;
    compilerFingerprint?: string;
    cacheHit: boolean;
  }
>;

export type AssistantRespondedEvent = ProjectEventEnvelope<
  'assistant.responded',
  {
    feedbackEventId: ProjectEventId;
    generationEventId: ProjectEventId;
    text: string;
  }
>;

export type SystemNotifiedEvent = ProjectEventEnvelope<
  'system.notified',
  {
    severity: 'info' | 'warning' | 'error';
    message: string;
    relatedEventIds: ProjectEventId[];
  }
>;

export type ProjectEvent =
  | ProjectCreatedEvent
  | ProjectRenamedEvent
  | FeedbackSubmittedEvent
  | AiGenerationRequestedEvent
  | AiGenerationSucceededEvent
  | AiGenerationFailedEvent
  | VisualizationRenderRequestedEvent
  | CompilationRequestedEvent
  | CompilationSucceededEvent
  | CompilationFailedEvent
  | ArtifactVersionCreatedEvent
  | VisualizationRenderedEvent
  | AssistantRespondedEvent
  | SystemNotifiedEvent;

export type ProjectEventType = ProjectEvent['type'];

type WithoutChainPosition<Event> = Event extends ProjectEvent
  ? Omit<Event, 'sequence' | 'parentEventId'>
  : never;

export type NewProjectEvent<Type extends ProjectEventType = ProjectEventType> =
  WithoutChainPosition<Extract<ProjectEvent, { type: Type }>>;

export type ProjectDocument = {
  schemaVersion: 1;
  projectId: ProjectId;
  events: ProjectEvent[];
};

export type ProjectSnapshot = {
  projectId: ProjectId;
  eventId: ProjectEventId;
  title: string;
  entryArtifactId: ArtifactId;
  artifacts: Record<ArtifactId, ProjectArtifact>;
  artifactVersionEventIds: Record<ArtifactId, ProjectEventId>;
  activeRender?: VisualizationRenderedEvent;
};

export type HydratedProjectArtifact = Omit<ProjectArtifact, 'content'> & { content: string };

export type ProjectPageState = {
  document: ProjectDocument;
  cursorEventId: ProjectEventId;
  headEventId: ProjectEventId;
  snapshot: Omit<ProjectSnapshot, 'artifacts'> & {
    artifacts: Record<ArtifactId, HydratedProjectArtifact>;
  };
  trace?: CompiledVisualization;
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

export type ProjectActionAck = {
  correlationId: ProjectCorrelationId;
  headEventId: ProjectEventId;
};

export type ProjectActionName = 'feedback' | 'rename' | 'render' | 'restore' | 'saveArtifact';
