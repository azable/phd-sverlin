export type JsonPatchOperation = {
  op: 'replace';
  path: '/content';
  value: string;
};

export type SourceArtifact = {
  id: 'dsl-main';
  path: 'compile/app/DSL/Main.sverlin';
  language: 'sverlin';
  content: string;
};

export type ArtifactChangeSource =
  | { kind: 'chat'; turnId: string; messageId?: string }
  | { kind: 'manual'; actor: 'user'; reason?: string }
  | { kind: 'feedback'; feedbackId: string };

export type ArtifactChangeEvent = {
  eventId: string;
  streamVersion: number;
  artifactId: SourceArtifact['id'];
  revision: number;
  previousRevision: number;
  before: SourceArtifact;
  after: SourceArtifact;
  patch: JsonPatchOperation[];
  source: ArtifactChangeSource;
  correlationId: string;
  createdAt: string;
};

export type ArtifactSyncState = {
  artifactId: SourceArtifact['id'];
  streamVersion: number;
  headRevision: number;
  current: SourceArtifact;
  events: ArtifactChangeEvent[];
};

export type ArtifactEditMode = 'readonly' | 'editing' | 'conflict';

/**
 * The complete artifact context supplied to a chatbot provider.
 *
 * `history` is deliberately not a window. Consumers can use the stream
 * metadata and event revisions to reconcile their own views without losing
 * provenance.
 */
export type ArtifactContext = {
  current: SourceArtifact;
  headRevision: number;
  streamVersion: number;
  history: ArtifactChangeEvent[];
};
