import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import type {
  ArtifactChangeEvent,
  ArtifactChangeSource,
  ArtifactContext,
  ArtifactSyncState,
  JsonPatchOperation,
  SourceArtifact
} from '$lib/artifacts/types';
import { dslSourcePath, persistSourceArtifact } from './source-file';

const sourcePath = dslSourcePath;
const initialSource = readFileSync(resolve(process.cwd(), sourcePath), 'utf8');
const initialArtifact: SourceArtifact = {
  id: 'dsl-main',
  path: sourcePath,
  language: 'sverlin',
  content: initialSource
};

let streamVersion = 0;
let headRevision = 0;
let current = initialArtifact;
let events: ArtifactChangeEvent[] = [];
let pendingMutation = Promise.resolve();

export function getArtifactSyncState(after?: number): ArtifactSyncState {
  const cursor = after === undefined ? undefined : Math.max(0, after);

  return structuredClone({
    artifactId: current.id,
    streamVersion,
    headRevision,
    current,
    // Never window this list. `after` is an incremental stream cursor, not a
    // retention policy; callers without a cursor receive the complete audit log.
    events: cursor === undefined ? events : events.filter((event) => event.streamVersion > cursor)
  });
}

export function getArtifactContext(): ArtifactContext {
  return structuredClone({
    current,
    headRevision,
    streamVersion,
    history: events
  });
}

export function appendArtifactChange(
  content: string,
  baseRevision: number,
  source: ArtifactChangeSource,
  correlationId: string
) {
  return enqueueMutation(() =>
    appendArtifactChangeNow(content, baseRevision, source, correlationId)
  );
}

async function appendArtifactChangeNow(
  content: string,
  baseRevision: number,
  source: ArtifactChangeSource,
  correlationId: string
) {
  if (baseRevision !== headRevision) {
    const conflict = new Error('Artifact revision is out of date.');
    conflict.name = 'ArtifactConflictError';
    throw conflict;
  }

  if (content === current.content) return getArtifactSyncState();

  const before = current;
  const after = { ...current, content };
  const patch: JsonPatchOperation[] = [{ op: 'replace', path: '/content', value: content }];
  const event: ArtifactChangeEvent = {
    eventId: crypto.randomUUID(),
    streamVersion: streamVersion + 1,
    artifactId: current.id,
    revision: headRevision + 1,
    previousRevision: headRevision,
    before,
    after,
    patch,
    source,
    correlationId,
    createdAt: new Date().toISOString()
  };

  await persistSourceArtifact(content);

  streamVersion = event.streamVersion;
  headRevision = event.revision;
  current = after;
  events = [...events, event];

  return getArtifactSyncState();
}

/** Reset the current source to its bootstrap content without deleting history. */
export function resetArtifactToInitial(correlationId = crypto.randomUUID()) {
  return enqueueMutation(async () => {
    if (current.content !== initialSource) {
      await appendArtifactChangeNow(
        initialSource,
        headRevision,
        { kind: 'manual', actor: 'user', reason: 'reset' },
        correlationId
      );
    }

    return getArtifactSyncState();
  });
}

function enqueueMutation<T>(mutation: () => Promise<T>): Promise<T> {
  const result = pendingMutation.then(mutation, mutation);
  pendingMutation = result.then(
    () => undefined,
    () => undefined
  );
  return result;
}
